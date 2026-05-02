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
