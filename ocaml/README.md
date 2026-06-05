# OCaml VOF

OCaml reference implementation of VOF data types and convenience utilities.  This module provides:

* A polymorphic variant matching the rich data types of VOF;
* Simple scalar types a compatible subset of `Yojson.Basic.t`;
* JSON encoding to/from `Yojson.Basic.t` without explicit dependency;
* CBOR codec built-in;
* Diff to create PATCH records;
* Cache to help with encoding efficiency;
* Typed decoding helper functions.

As of this version, the final encoding and decoding is left to the caller and the only dependencies are:

* `base64`
* `ipaddr`

Development dependencies add:

* `alcotest`
* `bisect-ppx`
* `qcheck` and `qcheck-alcotest`

## Installation

This package is not published on OPAM.  Two common approaches are:

### OPAM Pin

To install as a normal switch-level package pinned to a specific version:

```sh
opam pin add ocaml-vof 'git+https://github.com/vphantom/vof.git#v1.0.0'
```

Then add `ocaml-vof` to your `.opam` file's `depends` section.

### Vendored Submodule

Add this repository as a git submodule and let Dune discover it:

```sh
git submodule add https://github.com/vphantom/vof.git vendor/vof
```

In your project's root `dune` file, you probably want to suppress warnings from vendored code:

```
(vendored_dirs vendor)
```

Your libraries and executables can then depend on `vof` and `vof_lib` directly.

## Implementation Notes

* We use native `int` integers, which means that we cannot I/O full 64-bit.  Good compromise for business applications, not for things like IPv4 or truncated UUID values.
* There is no `Read.enum` helper, since in OCaml those are variants anyway.  Instead, `Read.variant` accepts enums gracefully.
* We use options for error management, since it's impractical to refer to locations of errors in source data.

## Coding Style

- MLI files should include a brief summary of key design decisions to help future developers get situated quickly.
- Prefer:
  - Sticking to the Stdlib
  - Immutability where possible
  - TMC vs using `List.rev`
  - `Buffer` or `Printf` vs chains of `^`
  - `function` when matching on the last argument
  - Pipes vs parentheses for call chains (i.e. `foo a |> bar |> baz`)
  - Most global function arguments first (for currying) and subjects last (for piping)
  - Pattern matches vs if/else chains
  - Local functions to avoid lambdas spanning multiple lines or nesting more than two matches
  - `Seq.t` to `List.t` as an intermediary for conversions to reduce allocations
- Naming conventions:
  - Converters with `of_X`/`to_X` pairs

### Errors, Flow Control

#### Development Errors

Errors which should never happen in production deserve full stack traces.

* `assert` — _avoid_, use `failwith "…"` or `if expr then failwith "…"`
* `failwith "…"` — theoretically impossible states like negative array positions
* `invalid_arg "Module.func: …"` — caller misuse (developer error) with helpful hint
* `raise A_custom_exception` — non-developer errors which should still not happen in production

#### Exceptions For Flow Control

For hot-path flow control where bubbling a result value is impractical, use `raise_notrace`.  Use Stdlib's `End_of_file`, `Exit` and `Not_found` where appropriate, create custom exceptions for anything else.  Use custom exceptions instead of `Exit` for internal flow control which should not leak to your caller, for disambiguation.

#### Return Values

When it is expected that a function may not return its normal result in production, use `option`.  When there is useful information to pass along in the error case, use `result` instead.

## Application Example

```ocaml
(* order.ml *)

open Vof

module Line = struct
  type t
  let vof_schema = ...

  (* Add to [?warn] before returning None, if necessary. *)
  let of_vof ctx ?warn v = ...

  let sm_key sm =
    let| v = StringMap.find_opt "i" sm in
    Read.uint v
  ;;
end

type t

let empty = { ... }
let vof_schema = ...

let sm_key sm =
  let| v = StringMap.find_opt "uid" sm in
  Read.uint v
;;

let db_get db uid = ...

let db_put db o =
  (* NOTE: we rely on db_get offering key/t caching to tolerate this dual call *)
  let orig = db_get db o.uid in
  match o.uid, orig with
  | 0, _ -> (* Generate key; INSERT all *)
  | uid, None -> (* INSERT all *)
  | _, Some orig -> (* UPDATE smartly *)
;;

let of_vof ctx ?db ?warn v =
  let open Read in
  let| sm = record ctx vof_schema Option.some v in
  let base =
    let| db = db in
    let| uid = sm_key sm in
    db_get db uid |> Option.value ~default:empty
  in
  each_field ?warn (vof_schema, sm) base @@ fun k v acc ->
  match k with
  (* Probably prevent modifying non-default UID here *)
  | "uid" -> { acc with uid = field uint v }
  (* Check timestamp compatibility *)
  | "email" -> { acc with email = field string ~null:empty.email v }
  | "total" -> { acc with total = field decimal ~null:empty.total v }
  | "lines" -> (
    let lines = children ctx Line.vof_schema ?warn
      ~of_vof:(Line.of_vof ctx ?warn)
      ~key_of:(fun l -> l.i)
      ~key_read:Line.sm_key
      acc.lines v
    in
    { acc with lines = Option.value ~default:acc.lines lines }
  )
  | _ -> acc
;;
```
