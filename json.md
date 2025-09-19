# Vanilla Object Format — JSON

Regular JSON with some typing and formatting conventions directly interchangeable with VOF binary.

The following high-level types are standard (to be preferred to alternatives) but optional (implemented as needed).  They are not distinguished explicitly on the wire: applications agree out-of-band about when to use what, much like Protobuf, Thrift, etc.

| Name                   | JSON Encoding                                                            |
| ---------------------- | ------------------------------------------------------------------------ |
| `null`                 | Null                                                                     |
| `bool`                 | Boolean                                                                  |
| `list`/`…s`            | Array                                                                    |
| `map`                  | Object                                                                   |
| `variant`/`enum`       | Array[`string`,args…] / `string` with first or all letters uppercased    |
| `struct`/`obj`         | Object with field name keys                                              |
| `string`/`str`         | String (necessarily UTF-8)                                               |
| `bytes`/`data`         | String Base64-URL                                                        |
| `decimal`/`dec`        | String: optional `-`, then either 1+ digits or 0+ digits, `.`, 1+ digits |
| `uint`                 | Number within JS `MAX_SAFE_INTEGER`, `decimal` otherwise                 |
| `int`                  | Number within JS `MIN/MAX_SAFE_INTEGER`, `decimal` otherwise             |
| `ratio`                | String: optional `-`, 1+ digits, `/`, 1+ digits                          |
| `percent`/`pct`        | `decimal` rebased to 1 (i.e. 50% is ".5")                                |
| `float16`/`f16`        | `bytes` IEEE 754 binary16 Little Endian                                  |
| `float32`/`f32`        | `bytes` IEEE 754 binary32 Little Endian                                  |
| `float64`/`f64`        | `bytes` IEEE 754 binary64 Little Endian                                  |
| `float128`/`f128`      | `bytes` IEEE 754 binary128 Little Endian                                 |
| `float256`/`f256`      | `bytes` IEEE 754 binary256 Little Endian                                 |
| `mask`                 | `list` of a mix of `string` and `list` (see below)                       |
| `date`/`_on`           | `uint` as YYYYMMDD (see below)                                           |
| `datetime`/`time`      | `uint` as YYYYMMDDHHMM (see below)                                       |
| `timestamp`/`ts`/`_at` | `int` seconds since UNIX Epoch `- 1,750,750,750`                         |
| `timespan`/`span`      | `list` of three `int` (see below)                                        |
| `id`/`guid`/`uuid`     | `uint` or `string` depending on source type                              |
| `code`                 | `string` strictly uppercase alphanumeric ASCII (i.e. "USD")              |
| `language`/`lang`      | `code` IETF BCP-47                                                       |
| `country`/`cntry`      | `code` ISO 3166-1 alpha-2                                                |
| `region`/`rgn`         | `code` ISO 3166-2 alpha-1/3 (without country prefix)                     |
| `currency`/`curr`      | `code` ISO 4217 alpha-3                                                  |
| `unit`                 | `code` UN/CEFACT Recommendation 20 unit of measure                       |
| `text`                 | `map` of `lang,string` pairs / `string` for just one in a clear context  |
| `amount`/`price`/`amt` | String: `decimal` and optionally space a `currency` (i.e. "1.23 CAD")    |
| `quantity`/`qty`       | String: `decimal` and optionally space a `unit` (i.e. "1.23 GRM")        |
| `ip`                   | `string` IPv4 or IPv6 notation                                           |
| `subnet`/`cidr`/`net`  | `string` CIDR notation                                                   |

## Canonical Encoding

* When possible, Objects should be sorted by ascending key when buffering the whole list is possible, to facilitate higher-level compression.

* Number, `decimal` and `ratio` must strip leading zeros and trailing decimal zeros.

* Floating point numbers must be represented in the smallest form which does not lose precision.  Note that `-0.0` and `+0.0` are _not_ considered equivalent, however all `NaN` bit patterns are considered equal.  When converting between precisions, denormalized numbers should be normalized if the target precision can represent the exact value as a normal number.  This ensures minimal representation while maintaining precision.  Note that 128 and 256 bit floating point support is not expected under normal circumstances and should only be used when readers are expected to support them.

## Additional Notes on Types

### Date, Datetime

Calendar and wall clock time.  Time zone is outside the scope of this type, derived from context as necessary.

## Timespan

Calendar duration expressed as half-months, days and seconds, each signed and applied in three steps in that order when it is used.

### Code

Codes prefixed with `_` are reserved for user-defined alternatives anywhere `code` is used (i.e. a custom language `FR` in the negative space would be distinct from positive `FR`, which is standard in IETF BCP-47).  While the use of custom codes is discouraged, this scheme makes it possible.

Note on binary interoperability: because codes are numeric in binary VOF, leading zeros, while valid in JSON, would be truncated by a binary conversion.  Therefore, standard and custom codes should never begin with leading zeros.

### Struct

Similar to Protobuf's messages, their fields are named and should remain reserved forever when they are deprecated to avoid version conflicts.

### Text

If multiple strings are provided with the same language code, the first one wins.  Used in its bare `string` form, it is up to the applications to agree on the choice of default language.

The canonical encoding is to use the bare `string` form when a single language is used and corresponds to the default language (if one is defined), to minimize space.

### Mask

Equivalent to Protobuf's FieldMask.  In the context of a specific `struct` definition, an associated `mask` is `list` of field names where any field may be wrapped in a `list` in order to select its child `struct`'s fields as well.  For example, fields "id", "name", "user", "type" where "user" is a sub-structure of which we want field "country" only would be encoded as: `["id","name",["user","country"],"type"]`.  Useful in RPC where a service may declare which fields are available or a client may request a limited subset of available data (similar to SQL `SELECT`, PostgREST's "Vertical Filtering" or GraphQL).

### References

References at our level are much more efficient than an external compression scheme would be (i.e. gzip) because references let decoders reuse the same decoded resources, without having to expose a distinction between references by ID vs full inclusion at the application level.  This lets API designers include child objects uniformly in their schemas without worrying about redundancy in memory nor on the wire.

To keep implementations light and efficient, support is limited to the specific but highly useful scenario of a `struct` with a key named `guid` or `uuid`. Those keys are considered globally unique, so when encoders encounter such objects more than once, they may replace duplicates with their unwrapped `guid` or `uuid` value (in that order of preference).  This is unambiguous because a Number or String is encoded where an Object is expected.

**NOTE:** Some encoding or decoding libraries may reorder JSON structures such that decoding applications may sometimes encounter references before the full Object. This means that implementations should wrap their application-facing API `struct` type with a mutable "ID or struct" kind of object to be resolved when the full object is eventually decoded.

For applications with table-specific ID namespaces, one strategy to benefit from references could be to fake GUIDs on the wire by prefixing a namespace to the ID.  For example, a single character followed by a Base-32 Crockford encoding of the ID could be readable yet short, such that "color 1234" might be "C16J", or "size 515" could be "SG3".

Full example:

```json
{
   "servers": {
      "load_balancer": { "guid": "BAF86644", "name": "DO-Toronto VPS 5" },
      "frontend": { "guid": "BACF5222", "name": "DO-Toronto VPS 3" },
      "backend": "BACF5222"
   },
   "events": [
      { "date": "2020-01-01", "user": { "guid": 8395767312, "name": "First User" }, "act": "Other" },
      { "date": "2020-01-02", "user": { "guid": 649368382, "name": "Second User" }, "act": "Other" },
      { "date": "2020-01-03", "user": 8395767312, "act": "Login" },
      { "date": "2020-01-04", "user": 8395767312, "act": "Logout" },
      { "date": "2020-01-05", "user": 649368382, "act": "Login" },
   ]
}
```

### User-Defined Types

Tags are represented in JSON as objects with a single member whose key is a string starting with "@" followed by a number 0..63, with the value being the tagged value. For example, a user-defined "URL" type could be decided as `{"@0": "https://example.com"}`. Such tags may have completely different meanings across different applications, so their use makes the resulting data non-portable. Decoders should fail when presented with unknown tags.

## Implementation Considerations

### Large Precision Numbers

JSON libraries without support for 128 or 256 bit numbers should fail when presented with such values.

### String Validation

Since strings are expected to be valid UTF-8, encoders and decoders should fail when presented with invalid UTF-8.

### Reference Tracking

The index of references maintained by decoders should use `string` keys (thus converting numeric references to `string` ones) to avoid imposing a possible distinction between equivalent values of both types to encoders.

### Decoding Security

Implementations should consider reasonable limits on:

* Total nesting depth (128 might be reasonable)
* Maximum string length (1MB to 1GB might be reasonable)
* Maximum number of object members (1K might be reasonable)
