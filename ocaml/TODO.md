# TODO

- [ ] Tests, lots and lots of tests...  We might need: alcotest, qcheck, qcheck-alcotest for testing, `bisect_ppx` for coverage reporting, bechamel for benchmarking if we want to also catch performance regressions.  (See my Paragon project for example use of all of those.)
- [ ] Helper to detect which wire format we're reading (JSON, CBOR, Binary, Gzip, Zstd)
