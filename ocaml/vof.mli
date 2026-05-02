(** Vanilla Object Format

    Serialize to/from the VOF wire formats.

    Much like with Yojson or SexpLib, there is a main type [t] which needs
    corresponding [to_vof] and [of_vof] functions for every type to serialize.
    The recommended pattern for each domain type is:

    {[
    (** Construct a fully-typed VOF value from a domain object. Used for
        encoding to any wire format. *)
    val to_vof : 'a -> Vof.t

    (** Construct a domain object from a VOF value. Uses {!Vof.Reader} helpers
        internally to interpret both fully-typed values and raw wire
        representations. For patchable records, the result may be a partial
        record (subset of fields). *)
    val of_vof : Vof.t -> 'a option
    ]} *)

module StringSet : Set.S with type elt = string
module StringMap : Map.S with type key = string
module IntMap : Map.S with type key = int

type schema = { path: string; keys: string list; required: string list }
type decimal = int * int
type ratio = int * int
type date = { year: int; month: int; day: int }
type datetime = { year: int; month: int; day: int; hour: int; minute: int }
type timespan = { hmonths: int; days: int; secs: int }

(** Single value *)
type t =
  | Null
  | Bool of bool
  | Int of int
  | Uint of int
  | Float of float
  | String of string
  | Data of bytes
  | Enum of schema * string
  | Variant of schema * string * t list
  | Decimal of decimal
  | Ratio of ratio
  | Percent of decimal
  | Timestamp of int
  | Date of date
  | Datetime of datetime
  | Timespan of timespan
  | Code of string
  | Language of string
  | Country of string
  | Subdivision of string
  | Currency of string
  | Tax_code of string
  | Unit of string
  | Text of string StringMap.t
  | Amount of decimal * string option
  | Tax of decimal * string * string option
  | Quantity of decimal * string option
  | Ip of bytes
  | Subnet of bytes * int
  | Coords of float * float
  | Strmap of t StringMap.t
  | Uintmap of t IntMap.t
  | List of t list
  | Ndarray of int list * t array
  | Record of record
  | Series of record list
  | Raw_bint of int
  | Raw_blist of t list
  | Raw_bstr of string
  | Raw_gap of int
  | Raw_int of int
  | Raw_list of t list
  | Raw_tag of int * t
  | Raw_tint of int
  | Raw_tlist of t list
  | Raw_tstr of string

(** Record *)
and record = schema * t StringMap.t

module Context : sig
  (** Encoding context.

      Maintains a registry of namespace indices mapping symbolic field and
      variant names to compact integer identifiers. Supports persistence via
      {!load} and {!save} for incremental schema evolution.

      When [update] mode is enabled, encountering unknown symbols auto-registers
      them. Otherwise, unknown symbols raise [Invalid_argument]. *)

  (** Opaque index for a single namespace (one schema path). *)
  type index

  (** Mutable context holding the full registry of namespaces. *)
  type t

  (** A named record fetcher for expanding references during selection. *)
  type fetcher = string * (record -> record option)

  (** [make ?update root] creates a fresh context rooted at [root]. When
      [update] is [true] (default [false]), unknown symbols are auto-registered
      and schema hints may evolve the registry. *)
  val make : ?update:bool -> string -> t

  (** [load ctx path] populates [ctx] from a symbol table file at [path]. The
      context registry must be empty. If [update] is [true] and the file does
      not exist, the context starts empty. *)
  val load : t -> string -> unit

  (** [save ctx] persists the current registry to the file set via {!load}.
      Requires [update] mode. No-op if nothing was modified since loading. *)
  val save : t -> unit

  (** [schema ctx ?keys ?required rel_path] declares or retrieves a schema for
      the namespace at [rel_path] (relative to the context root). If the
      namespace already exists and hints are provided, they are validated (or
      updated in update mode). *)
  val schema :
    t -> ?keys:string list -> ?required:string list -> string -> schema

  (** [add_fetchers ctx fl] registers record fetchers keyed by namespace path,
      used for expanding references. *)
  val add_fetchers : t -> fetcher list -> unit

  (** [lookup ctx path] returns the index for the absolute namespace [path],
      creating one if in update mode. *)
  val lookup : t -> string -> index

  (** [lookup_id ctx path sym] returns the integer id for symbol [sym] in the
      namespace at [path]. *)
  val lookup_id : t -> string -> string -> int

  (** [idx_id ctx idx sym] returns the integer id for symbol [sym] in [idx],
      auto-registering in update mode. *)
  val idx_id : t -> index -> string -> int

  (** [idx_sym idx id] returns the symbol name for integer [id], or [None] if
      out of range. *)
  val idx_sym : index -> int -> string option
end

module Reader : sig
  (** Schema-guided value interpretation.

      Each helper accepts a VOF value in any representation — fully typed, raw
      binary, raw text, or raw CBOR — and attempts to produce the corresponding
      OCaml value. Returns [None] on type mismatch or malformed input. Use these
      inside your [of_vof] functions. *)

  val int : t -> int option
  val uint : t -> int option
  val bool : t -> bool option
  val float : t -> float option
  val string : t -> string option
  val code : t -> string option
  val language : t -> string option
  val country : t -> string option
  val subdivision : t -> string option
  val currency : t -> string option
  val tax_code : t -> string option
  val unit_ : t -> string option
  val data : t -> bytes option
  val decimal : t -> decimal option
  val ratio : t -> ratio option
  val percent : t -> decimal option
  val timestamp : t -> int option
  val date : t -> date option
  val datetime : t -> datetime option
  val timespan : t -> timespan option
  val amount : t -> (decimal * string option) option
  val quantity : t -> (decimal * string option) option
  val tax : t -> (decimal * string * string option) option
  val coords : t -> (float * float) option
  val ip : t -> bytes option
  val subnet : t -> (bytes * int) option
  val strmap : (t -> 'a option) -> t -> 'a StringMap.t option
  val text : t -> string StringMap.t option
  val uintmap : (t -> 'a option) -> t -> 'a IntMap.t option
  val list : (t -> 'a option) -> t -> 'a list option
  val ndarray : (t -> 'a option) -> t -> (int list * 'a array) option

  val variant :
    Context.t ->
    schema ->
    (string -> t list -> string option) ->
    t ->
    string option

  val record :
    Context.t -> schema -> (t StringMap.t -> 'b option) -> t -> 'b option

  val series :
    Context.t -> schema -> (t StringMap.t -> 'c option) -> t -> 'c list option
end

(** [equal a b] is structural equality for VOF values. Unlike polymorphic [=],
    this correctly handles [Float] (via [Float.equal]), maps, arrays, and
    ignores schema identity in records/enums/variants. *)
val equal : t -> t -> bool

(** [diff a b] computes a PATCH record representing the minimal changes needed
    to transform [a] into [b]. Both values must be {!Record}s with the same
    schema. Key fields are preserved for identification; unchanged fields are
    omitted; removed fields appear as {!Null}. Nested records and series are
    diffed recursively. Returns [None] if the inputs are not both records. *)
val diff : t -> t -> t option
