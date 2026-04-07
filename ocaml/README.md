# OCaml VOF

OCaml reference implementation of VOF data types and convenience utilities.  This module provides:

* A polymorphic variant matching the rich data types of VOF;
* Scalar types compatible with `Yojson.Basic.t`;
* Encoding and decoding in JSON using `Yojson.Basic.t`;
* Diff to create PATCH records;
* Cache to help with encoding efficiency;
* Typed decoding helper functions.

As of this version, the final encoding and decoding is left to the caller and the only dependencies are:

* `base64`
* `ipaddr`

CBOR and binary support are not yet implemented.
