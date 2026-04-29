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

* Server API helpers are not implemented
* CBOR and Binary I/O are not implemented.

## LLM Use Disclosure

Porting from the OCaml reference implementation to Perl was done in part with tightly supervised assistance from Anthropic Claude Opus 4.6.  No code was generated from specs alone.
