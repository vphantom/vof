# TODO

- [ ] Refactor `Context.schema` as `Context.add_schema`, move documentation about its fields in MLI up to its type definition.
- [ ] Tests, lots and lots of tests...  We might need: alcotest, qcheck, qcheck-alcotest for testing, `bisect_ppx` for coverage reporting, bechamel for benchmarking if we want to also catch performance regressions.  (See my Paragon project for example use of all of those.)
- [ ] Try a few real-world records for business use, see where the biggest boilerplate pain points are, to see if we can add some helper functions or if maybe a PPX could help significantly.
- [ ] Helper to detect which wire format we're reading (JSON, CBOR, Binary, Gzip, Zstd)
