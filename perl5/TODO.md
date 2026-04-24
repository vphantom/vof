# Perl VOF implementation

Goals:

* Client-side core library, helpers for the type system
* JSON codec
* Structured to facilitate the addition of CBOR and Binary codecs later (i.e. stub `VOF::Context` passed around but not actually used yet)
* Series uses string field order, since for now there's no context to get integer IDs from.
* No server-side helpers (PATCH generation, `select~` processing)
* Testing, since this will be used in production

Relevant files from the OCaml implementation: `vof.ml`, `vof_lib.ml`, `vof_json.ml`

## Structure

### `VOF.pm`

* Blessed value wrappers (single class with a type tag, or small hierarchy) with exported constructor functions: `vof_decimal("12.50")`, `vof_date(2025,12,31)`, etc.
* Decimal, Date, Datetime, etc. helpers to/from string

### `VOF/Schema.pm`

Simple constructor for path, keys, required like in OCaml.  Allows helpers like:

```perl
# Distinguish a full record from a mere reference
sub is_reference {
    my ($schema, $fields) = @_;
    my %allowed = map { $_ => 1 } @{$schema->{keys}}, @{$schema->{required}};
    return !grep { !$allowed{$_} } keys %$fields;
}
```

### `VOF/JSON.pm`

* `encode($vof_value)` — unblessed Perl structure ready for `JSON::encode_json()`, making use of `JSON::true` and `JSON::false` for Bool.  Remember to stringify integers beyond 2^53-1.
* `decode($perl_structure)` — returns raw VOF values
* Reader functions like OCaml's, schema-driven interpreters like `read_decimal()`, `read_date()`, etc.

## Design Decisions

* A single `VOF::Value` class (blessed `[$type_tag,@payload]`)
* Reader pattern like in OCaml, like `vof_read_record($ctx, $schema, $raw, sub { my ($fields) = @_; ... })`
* It's okay to depend on JSON (or JSON::XS) and MIME::Base64.  Let's see if we need NetAddr::IP or manual formatting.
