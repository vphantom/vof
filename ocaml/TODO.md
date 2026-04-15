# TODO

## Records, Series

- [ ] Series encoding should iterate through the list of records to collect all fields, instead of relying on the first record, in order to eliminate the case where surprising fields caused the whole thing to fail.
- [ ] JSON series encoding should sort by integer ID instead of string name, so that schema additions are appended over time.  This means adding context arguments where needed.

## MLI notes

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

## API Helpers

After JSON and CBOR are fully implemented, we'll see more clearly how to add API
helpers.  We definitely need something to help with `select~` filtering, and any
other boilerplate we can help reduce.
