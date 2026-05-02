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
- Dependencies: Stdlib plus as few specific helpers as possible
- Error handling:
  - Reserve exceptions for fatal errors (i.e. OOM), developer errors which should never make it to production (i.e. `invalid_arg` on array index out of bounds or `assert false` on unacceptable match case) and `raise_notrace` for I/O signaling (i.e. EOF) and for early returns in hot paths.  Use the result and option types when other conditions are possible.
