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

(** {1 Core Types} *)

module StringSet : Set.S with type elt = string
module StringMap : Map.S with type key = string
module IntMap : Map.S with type key = int

type schema = {
  path: string;
  msg_field: string option;
  keys: string list;
  required: string list;
}

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

(** {1 Context} *)

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
  type fetcher = string * (record -> (record, string) result)

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

  (** [schema ctx ?msg_field ?keys ?required rel_path] declares or retrieves a
      schema for the namespace at [rel_path] (relative to the context root). If
      the namespace already exists and hints are provided, they are validated
      (or updated in update mode).

      [msg_field] is the name of the field in your [$msg] schema containing a
      list of records of this type.

      [keys] are lists of field names which combine to form a record's primary
      key.

      [required] are fields which should be included along with keys even in
      references. *)
  val schema :
    t ->
    ?msg_field:string ->
    ?keys:string list ->
    ?required:string list ->
    string ->
    schema

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

(** {1 Decoding} *)

module Reader : sig
  (** Schema-guided value interpretation.

      Each helper accepts a VOF value in any representation — fully typed, raw
      binary or raw text — and attempts to produce the corresponding OCaml
      value. Returns [None] on type mismatch or malformed input. Use these
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

(** [pp_ref r] returns a string representation of a record reference as
    ["path(key1,key2...;required1,required2,...)"] where key values are followed
    by required values, both in the order in which they were declared in the
    schema. A non-reference gets the same treatment, but adds a third section
    ["; ..."] to indicate that it has additional fields. *)
val pp_ref : record -> string

(** [pp v] returns a string representation of basic types, ["?"] otherwise. Uses
    [pp_ref] for records. *)
val pp : t -> string

(** {1 Records} *)

(** [is_ref r] returns true if [r] is a record reference (no field outside of
    keys and required). *)
val is_ref : record -> bool

(** [make_ref r] strips record [r] of fields outside of keys and required. *)
val make_ref : record -> record

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

(** {1 Services}

    HTTP API endpoint helpers to parse query parameters, filter record fields
    and prepare [$msg] responses. Row filtering (including pruning) and
    pagination are left to the application. *)

(** {2 Warnings} *)

type warning = [
  | `Vof_unknown_param of string
  | `Vof_invalid_param of string * string
  | `Vof_fetch_failed of string * string
] [@@ocamlformat "disable"]

(** Your list of warnings. Note that this module adds warnings to the head of
    this list, so it is chronologically reversed. *)
type warnings = warning list ref

(** [pp_warn w] returns a string representation of a warning, in simple English.
*)
val pp_warn : warning -> string

(** {2 Queries} *)

(** Parsed [select~] parameter. A field is selected when
    [(star && not excluded) || included || expanded || attached].

    - [expand] maps field names to sub-selections for inline expansion
      ([foo(…)]).

    - [attach] maps field names to sub-selections for [$msg] attachment
      ([$foo(…)]). *)
type selection = {
  star: bool;
  excludes: StringSet.t;
  includes: StringSet.t;
  expand: selection StringMap.t;
  attach: selection StringMap.t;
}

(** Everything empty and [star = true]. *)
val default_selection : selection

type filter_op =
  | Eq of string
  | Lt of string
  | Lte of string
  | Gt of string
  | Gte of string
  | Between of string * string
  | Has of string
  | In of string list

type filter = { field_path: string list; negate: bool; op: filter_op }

type query = {
  select: selection; (** Defaults to [default_selection] *)
  prune: StringSet.t;
  filters: filter list;
  max: int;
  page: int;
}

(** [make_query ?warn params] Create a query from a list of key-value pairs.
    Malformed [select~] gracefully downgrades to ["*"] and incorrect filters are
    ignored. Specify [warn] to collect warnings. *)
val make_query : ?warn:warnings -> (string * string) list -> query

(** {2 Messages}

    Build and update [$msg] records. *)

(** Records aggregated by type and de-duplicated by key tuples. *)
type msg

(** [build_msg ctx q ?msg v] Create/update [?msg] by processing record, series
    or record list [v] with query [q] in context [ctx], returning the
    accumulated [msg] and the filtered down [v]. Specify [warn] to collect
    warnings. Duplicate records preserve the one with the most fields set. *)
val build_msg : Context.t -> ?warn:warnings -> query -> ?msg:msg -> t -> msg * t

(** [msg_record ms msg] creates an [$msg] with [schema] from [msg]. *)
val msg_record : schema -> msg -> record
