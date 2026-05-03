# TODO

### Other Tasks

- [ ] `select` and `build_msg` API helpers
- [ ] Tests, lots and losts of tests...  We might need: alcotest, qcheck, qcheck-alcotest for testing, `bisect_ppx` for coverage reporting, bechamel for benchmarking if we want to also catch performance regressions.  (See my Paragon project for example use of all of those.)
- [ ] Try a few real-world records for business use, see where the biggest boilerplate pain points are, to see if we can add some helper functions or if maybe a PPX could help significantly.
- [ ] Helper to detect which wire format we're reading (JSON, CBOR, Binary, Gzip, Zstd)

## API Helpers

```ocaml
type selection = {
  star: bool;
  excludes: StringSet.t;
  includes: StringSet.t;
  expand: selection StringMap.t;
  attach: selection StringMap.t;
}

type filter_op =
  | Eq of string
  | Lt of string
  | Lte of string
  | Gt of string
  | Gte of string
  | Between of string * string
  | Has of string
  | In of string list

type filter = {
  path: string list;  (* "lines.product" -> ["lines";"product"] *)
  negate: bool;
  op: filter_op;
}

type query = {
  select: selection;
  prune: StringSet.t;
  filters: filter list;
  max: int;
  page: int;
  params: (string * string) list;
}

type warning = [
  | `Vof_malformed_select of string
  | `Vof_malformed_filter of string
  | `Vof_fetch_failed of string * string
]

(** [is_ref r] returns true if [r] is a record reference (no field outside of
    keys and required). *)
val is_ref : record -> bool

(** Your list of warnings.  Note that this module adds warnings to the head of
    this list, so it is chronologically reversed. *)
type warnings = warning list ref

(** [pp v] returns a string representation of common scalars, ["?"] otherwise.
    Record references are returned as [("path(key1,key2...)")] but populated
    records are ["?"] like other complex types. *)
val pp : t -> string

(** [pp_ref r] returns a string representation of a record reference as
    ["path(key1,key2...)"]. *)
val pp_ref : record -> string

(** [pp_warn w] returns a string representation of a warning, in simple English. *)
val pp_warn : warning -> string

(** Aggregated records and record references. *)
type msg = (record KeyMap.t) StringMap.t

(** [make_query ?warn params] Create a query from a list of key-value pairs.
    Malformed [select~] gracefully downgrades to ["*"] and incorrect filters are
    ignored.  Specify [warn] to collect warnings.  *)
val make_query : ?warn:warnings -> (string * string) list -> query

(** [select ctx s v] Filter record, series or record list [v] with selection [s]
    in context [ctx].  Specify [warn] to collect warnings.  Note that [attach]
    keys are handled by [build_msg], not here. (NOTE: not in the MLI) *)
val select : Context.t -> ?warn:warnings -> selection -> t -> t

(** [build_msg ctx q ?msg v] Create/update [?msg] by processing record, series
    or record list [v] with query [q] in context [ctx], returning the
    accumulated [msg] and the filtered down [v].  Specify [warn] to collect
    warnings.  Duplicate records prefer the ones with the most fields set. *)
val build_msg : Context.t -> ?warn:warnings -> query -> ?msg:msg -> t -> msg * t

(** [msg_record ms msg] creates an [$msg] with [schema] from [msg]. *)
val msg_record : schema -> msg -> record
```

The `msg` type is opaque to our callers (`type msg` without `=`).

A field is selected if `(star && not excluded) || included || expanded || attached` and the default `star` is true.

Our library handles column filtering and msg accumulation but leaves row filtering (including pruning child records) and pagination up to the application, since it is a data source level concern (i.e. DB).

It is up to the calling application to formulate a proper `$msg` from an msg, but at least thanks to schema paths we can correctly accumulate records of each type in there, de-duplicated.

When the selection calls for a full record and we only have a reference, use the context's fetcher for the current namespace path and fall back to keeping the reference if there's none or it doesn't succeed.  For `foo()` this would replace the reference by the whole thing before continuing with processing (filtering, etc.) and for `$foo()` this means leaving the reference in place and adding the (filtered) record to the `msg`.
