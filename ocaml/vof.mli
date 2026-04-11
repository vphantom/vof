(** Vanilla Object Format

    Serialize to/from the VOF wire formats.

    Much like with Yojson or SexpLib, there is a main type [t] which needs
    corresponding [to_vof] and [of_vof] functions for every type to serialize.
    To facilitate handling creation vs modification tasks, decoding should use
    an update pattern like:

    {[
      val of_vof : ?base:t -> Vof.value -> (t, error) result
    ]} *)

(** {1 Contexts} *)

(** Context for the current company/API. *)
type context

(** [make_context ?path ()] creates a new context. If [?path] is specified, a
    symbol namespace will be loaded from that path.  If [?update] is true, the
    file will be created if missing and updated if incomplete as record fields
    and enum/variant symbols are encountered. *)
val make_context : unit -> context

(** {1 Sources} *)

(** Mutable source of VOF values. *)
type source

(** [make_source ctx] creates a new source within [ctx]. *)
val make_source : context -> source
(* FIXME: what will those actually be? a variant between a Yojson tree, a CBOR
   one or a primitive VOF Binary one? *)

(** {1 Data Types} *)

module StringMap : Map.S with type key = string
module IntMap : Map.S with type key = int

module Decimal : sig
  type t = int * int
  val of_string : string -> (t, error) result
  val to_string : t -> string
end

module Ratio : sig
  type t = int * int
  val of_string : string -> (t, error) result
  val to_string : t -> string
end

type record = [ `Record of namespace * t StringMap.t ]

(** Namespace for compact binary encodings (Enum, Variant, Record). *)
type namespace = string

(** Single value *)
type t = [
  `Null
  | `Bool of bool
  | `Int of int
  | `Uint of int
  | `Float of float
  | `String of string
  | `Data of bytes
  | `Enum of namespace * string
  | `Variant of namespace * string * t list
  | `Decimal of Decimal.t
  | `Ratio of Ratio.t
  | `Percent of Decimal.t
  | `Timestamp of int
  | `Date of Unix.tm
  | `Datetime of Unix.tm
  | `Timespan of int * int * int
  | `Code of string
  | `Language of string
  | `Country of string
  | `Subdivision of string
  | `Currency of string
  | `Tax_code of string
  | `Unit of string
  | `Text of string StringMap.t
  | `Amount of Decimal.t * string option
  | `Tax of Decimal.t * string option * string option
  | `Quantity of Decimal.t * string option
  | `Ip of bytes
  | `Subnet of bytes * int
  | `Coords of float * float
  | `Strmap of t StringMap.t
  | `Intmap of t IntMap.t
  | `List of t list
  | `Ndarray of int list * t list
  | record
  | `Series of record list
] [@@ocamlformat "disable"]

(** [diff a b] returns the API PATCH to apply to [a] to obtain [b]. Raises
    [Invalid_argument] if [a] or [b] are not record types. *)
val diff : t -> t -> t

(* FIXME: diff needs to preserve primary key fields despite them not changing. I
   guess a StringSet.t? Just for typically 1-6 field names, though? *)

(* If we modify source immutably: *)
val expect_int : source -> (int * source, error) result
val expect_date : source -> (Unix.tm * source, error) result

(* Mutable cursor: *)
val expect_datetime : source -> (Unix.tm, error) result

(** {1 Encodings} *)

(** {2 JSON} *)

(* JSON data, compatible with [Yojson.Basic.t] *)
type json = [
  `Null
  | `Bool of bool
  | `Int of int
  | `Float of float
  | `String of string
  | `Assoc of (string * t) list
  | `List of t list
] [@@ocamlformat "disable"]

(** [to_json v] encodes [v] to the VOF JSON wire format. *)
val to_json : t -> json

(** [of_json v] prepares [v] for decoding. *)
val of_json : json -> source

(** {1 References}

    Encoding typically involves modules' [to_vof] calling each other
    recursively. To make sure that the generated [Vof.t] only encodes distinct
    records once (i.e. inlined products in order lines), applications can use
    caching by a global key type.

    {[
      let to_vof ?(cache = Vof.make_cache ()) val =
        Vof.cached cache val.id @@ fun () ->
        ...pass cache to any other to_vof calls
    ]} *)

type 'k cache

(** [make_cache ()] returns a new empty cache. *)
val make_cache : unit -> 'k cache

(** [cached cache key f] returns the cached value for [key] if it exists,
    otherwise calls [f ()] to produce, cache and return the value. *)
val cached : cache -> 'k -> unit -> t
