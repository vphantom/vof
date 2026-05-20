# Perl 5 VOF

Perl 5 reference implementation of VOF data types and convenience utilities.  This module provides:

* Perl structures matching the rich data types of VOF;
* JSON encoding to/from the `JSON` module (PP or XS);
* Typed decoding helper functions.

As of this version, the final encoding and decoding is left to the caller and the only dependencies are:

* `JSON`
* `MIME::Base64`

## Implementation Notes

* There is no `as_enum` helper, since those are just variants without arguments.
* We return undef for normal decoding errors, since it's impractical to refer to locations of errors in source data.

## Known Limitations

* Server-side `$msg` helpers (de-duplication, query filtering, selection expansion) are not implemented; clients construct and read `$msg` records using the existing `vof_record` / `as_record` primitives (see the POD for examples).
* CBOR and Binary I/O are not implemented.
