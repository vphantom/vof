# TODO

### Other Tasks

- [ ] Create `select` and `build_msg` API helpers
- [ ] Create `vof.mli`
- [ ] See what other kind of API helpers we could add.  Any boilerplate we can help reduce (as we did with Reader).
- [ ] Tests, lots and losts of tests...  We might need: alcotest, qcheck, qcheck-alcotest for testing, `bisect_ppx` for coverage reporting, bechamel for benchmarking if we want to also catch performance regressions.  (See my Paragon project for example use of all of those.)
- [ ] Try a few real-world records for business use, see where the biggest boilerplate pain points are, to see if we can add some helper functions or if maybe a PPX could help significantly.

## About `vof.mli`

The MLI file is so old and partial, we'll probably start a new one from scratch.

One thing it should mention is the signature convention for per-type conversion
functions (a-la Yojson, etc.):

```ocaml
val to_vof   : t -> Vof.t
(* Construct a fully-typed VOF value from a domain object. *)

val of_vof   : Vof.t -> t option
(* Construct a domain object from a fully-typed VOF value. Strict: all required
fields must be present. *)

val read_vof : Vof.input -> Vof.t option
(* Schema-guided interpretation of wire data into a fully-typed VOF value.  For
patchable records, the result may be a partial record (subset of fields).  Uses
Vof.Reader helpers internally. *)
```
