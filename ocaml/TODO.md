# TODO

- [ ] Helper for interpreting PATCH into actions, classify fields as absent/unset/changed, classify child list items as insert/update/delete, working from raw wire values via Reader, facilitating how our caller will want to do things like confirm required field compatibility (typically a modification timestamp).  Care will be needed around the distinction of new vs updated.
- [ ] Refactor `build_msg` to extract a `make_msg` and an `add_to_msg` for _unfiltered_ (but still de-duplicated and largest-wins) accumulation, useful for client-side request building.
- [ ] Tests, lots and lots of tests...  We might need: alcotest, qcheck, qcheck-alcotest for testing, `bisect_ppx` for coverage reporting, bechamel for benchmarking if we want to also catch performance regressions.  (See my Paragon project for example use of all of those.)
- [ ] Try a few real-world records for business use, see where the biggest boilerplate pain points are, to see if we can add some helper functions or if maybe a PPX could help significantly.
- [ ] Helper to detect which wire format we're reading (JSON, CBOR, Binary, Gzip, Zstd)
