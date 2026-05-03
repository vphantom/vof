# TODO

### Other Tasks

- [ ] Some kind of helper function for interpreting a PATCH into some actions, i.e. a transaction of SQL queries.  (Our helpers wouldn't touch SQL per se, but help our callers formulate the necessary queries.)
- [ ] Tests, lots and lots of tests...  We might need: alcotest, qcheck, qcheck-alcotest for testing, `bisect_ppx` for coverage reporting, bechamel for benchmarking if we want to also catch performance regressions.  (See my Paragon project for example use of all of those.)
- [ ] Try a few real-world records for business use, see where the biggest boilerplate pain points are, to see if we can add some helper functions or if maybe a PPX could help significantly.
- [ ] Helper to detect which wire format we're reading (JSON, CBOR, Binary, Gzip, Zstd)

## API Helpers

### Implementation Steps

- [x] Update `vof.mli` and create stubs in `vof.ml` to allow compilation
- [x] Implement `is_ref`, `pp_ref`, `pp` (which uses `pp_ref`) and `pp_warn`
- [x] Implement `make_query`
- [ ] Implement `select`
- [ ] Implement `build_msg`
- [ ] Implement `msg_record`

### Details

The `msg` type is opaque to our callers (`type msg` without `=`).  When `build_msg` encounters a schema with `msg_field = None`, it will raise (probably `invalid_arg`).  We're making it optional so that our callers who don't need $msg handling don't have to bother naming it.  We'll key `msg` on schema.msg_field (not schema.path) to facilitate `msg_record`.

In `query`, it is understood that `$foo` / `$foo()` means that the '$' prefix is stripped and 'foo' is the actual symbol to process.

A field is selected if `(star && not excluded) || included || expanded || attached` and the default `star` is true.

Our library handles column filtering and msg accumulation but leaves row filtering (including pruning child records) and pagination up to the application, since it is a data source level concern (i.e. DB).

It is up to the calling application to formulate a proper `$msg` from an msg, but at least thanks to schema paths we can correctly accumulate records of each type in there, de-duplicated.

When the selection calls for a full record and we only have a reference, use the context's fetcher for the current namespace path and fall back to keeping the reference if there's none or it doesn't succeed.  For `foo()` this would replace the reference by the whole thing before continuing with processing (filtering, etc.) and for `$foo()` this means leaving the reference in place and adding the (filtered) record to the `msg`.
