# Perl VOF implementation

Goals:

* Client-side core library, helpers for the type system
* JSON codec
* Structured to facilitate the addition of CBOR and Binary codecs later (`VOF::Context` loads shared symbol table files for schema-driven reading)
* No server-side helpers (PATCH generation, `select~` processing)
* Testing, since this will be used in production

Relevant files from the OCaml implementation: `vof.ml`, `vof_lib.ml`, `vof_json.ml`

## Status

* [x] Skeleton PM files with POD and stubs: `VOF.pm`, `VOF/JSON.pm`
* [x] Implement `VOF::Context` (load symbol tables, schema lookup)
* [x] Implement `VOF.pm` helpers (decimal, ratio, date, datetime)
* [x] Implement `VOF.pm` constructors
* [x] Implement `VOF.pm` readers for bool and numeric types
* [x] Implement `VOF.pm` readers for string/data types
* [x] Implement `VOF.pm` readers for compound numeric types (amount, tax, quantity)
* [x] Implement `VOF.pm` readers for temporal types
* [x] Implement `VOF.pm` readers for ip, subnet, coords
* [x] Implement `VOF.pm` readers for collections (strmap, uintmap, text, list, ndarray)
* [x] Implement `VOF.pm` readers for enum, variant
* [x] Implement `VOF.pm` reader for record
* [x] Implement `VOF.pm` reader for series
* [ ] Implement `VOF/JSON.pm` decode (JSON → `RAW_T*` values)
* [ ] Implement `VOF/JSON.pm` encode (typed values → JSON-ready structures)
* [ ] IP address formatting (manual vs dependency — TBD)
* [ ] Tests

## Design Decisions

* Single `VOF::Value` blessed arrayref class with integer type tags — chosen over a subclass-per-type hierarchy for compactness and fast integer dispatch in readers (which pattern-match heavily).
* Type tag constants are auto-numbered via `BEGIN`/`qw()` — specific integers are unstable across releases and must not be serialized.
* Readers live in `VOF.pm` (format-agnostic), not in `VOF/JSON.pm`.  `JSON.pm::decode()` only wraps JSON into `VOF_RAW_T*` values; the shared readers then interpret those.  This avoids duplicating readers when CBOR/Binary codecs arrive.
* Reader prefix: `as_*` (e.g. `as_decimal`).  Constructor prefix: `vof_*` (e.g. `vof_decimal`).
* Readers return `undef` on type mismatch.  Constructors `croak` on invalid input.
* Context-driven schemas — `VOF::Context` loads symbol table files and builds schemas via `$ctx->schema($relative_path)`, automatically prepending the root namespace.  `VOF::Schema` is an internal data carrier, not part of the public API.  Optional `keys`/`required` hints in `schema()` allow validation against loaded data (server safety net) or standalone use (tests).
* Dependencies: `JSON` (core) and `MIME::Base64` (core).  Evaluate IP formatting needs when implementing network types.
