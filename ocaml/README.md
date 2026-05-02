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

## Implementation Notes

* We use native `int` integers, which means that we cannot I/O full 64-bit.  Good compromise for business applications, not for things like IPv4 or truncated UUID values.
* There is no `Reader.enum` helper, since in OCaml those are variants anyway.  Instead, `Reader.variant` accepts enums gracefully.
* We use options for error management, since it's impractical to refer to locations of errors in source data.

## Coding Style

- MLI files should include a brief summary of key design decisions to help future developers get situated quickly.
- Prefer:
  - Sticking to the Stdlib
  - Immutability where possible (i.e. a `StringMap` vs a `Hashtbl`)
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
