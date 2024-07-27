# Vanilla Object Format — JSON

Regular JSON with some typing and formatting conventions directly interchangeable with VOF binary.

The following high-level types are standard (to be preferred to alternatives) but optional (implemented as needed).  They are not distinguished explicitly on the wire: applications agree out-of-band about when to use what, much like Protobuf, Thrift, etc.

| Name                   | JSON Encoding                                                                       |
| ---------------------- | ----------------------------------------------------------------------------------- |
| `undefined`            | In a `struct`, the absence of a field                                               |
| `null`                 | Explicit null                                                                       |
| `list`/`…s`            | Array                                                                               |
| `map`                  | Object                                                                              |
| `struct`/`obj`         | Object with field name keys / String                                                |
| `string`/`str`         | String (necessarily UTF-8)                                                          |
| `bytes`/`data`         | String Base-64 URL                                                                  |
| `bool`                 | Boolean                                                                             |
| `enum`                 | `string` uppercase label                                                            |
| `variant`              | Array[`string`,args…] / `string`                                                    |
| `uint`                 | Number if in JS MAX_SAFE_INTEGER, `bytes` little-endian otherwise                   |
| `int`                  | Number if in JS MIN/MAX_SAFE_INTEGER, or `bytes` little-endian 2's complement       |
| `id`/`guid`/`uuid`     | `uint` or `string` depending on source type                                         |
| `code`                 | `string` strictly uppercase alphanumeric ASCII (i.e. "USD")                         |
| `binary`/`float`/`fp`  | Number for 16,32,64 bit precisions, `bytes` IEEE 754 for 128,256 bit precisions     |
| `decimal`/`dec`        | String: optional `-`, 1+ digits and optionally a period `.` and 1+ digits           |
| `ratio`                | String: optional `-`, 1+ digits, `/`, 1+ digits                                     |
| `percent`/`pct`        | `decimal` rebased to 1 (i.e. 50% is "0.5")                                          |
| `mask`                 | `list` of a mix of `string` and `list` (see below)                                  |
| `datetime`/`date`/`dt` | String: `YYYY-MM-DD hh:mm:ss [+-]hhmm` (time and UTC offset independently optional) |
| `timestamp`/`ts`       | `int` seconds since UNIX Epoch `- 1_677_283_227`                                    |
| `language`/`lang`      | `code` IETF BCP-47                                                                  |
| `country`/`cntry`      | `code` ISO 3166-1 alpha-2                                                           |
| `region`/`rgn`         | `code` ISO 3166-2 alpha-1/3 (no country prefix)                                     |
| `currency`/`curr`      | `code` ISO 4217 alpha-3                                                             |
| `unit`                 | `code` UN/CEFACT Recommendation 20 unit of measure                                  |
| `text`                 | `map` of `lang,string` pairs / `string` for just one in a clear context             |
| `amount`/`price`/`amt` | String: `decimal` and optionally a single space and a `currency` (i.e. "1.23 CAD")  |
| `quantity`/`qty`       | String: `decimal` and optionally a single space and a `unit` (i.e. "1.23 GRM")      |
| `ip`                   | `string` IPv4 or IPv6 notation                                                      |
| `subnet`/`cidr`/`net`  | `string` CIDR notation                                                              |

## Struct

Similar to Protobuf's messages, their fields are named and should remain reserved forever when they are deprecated to avoid version conflicts.

## Mask

Equivalent to Protobuf's FieldMask.  In the context of a specific `struct` definition, an associated `mask` is `list` of field names where any field may be wrapped in a `list` in order to select its child `struct`'s fields as well.  For example, fields "id", "name", "user", "type" where "user" is a sub-structure of which we want field "country" only would be encoded as: `["id","name",["user","country"],"type"]`.  Useful in RPC where a service may declare which fields are available or a client may request a limited subset of available data (similar to SQL `SELECT`, PostgREST's "Vertical Filtering" or GraphQL).

## References

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
