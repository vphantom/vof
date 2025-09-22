# Vanilla Object Format — JSON

Regular JSON with some typing and formatting conventions directly interchangeable with VOF binary.

The following high-level types are standard (to be preferred to alternatives) but optional (implemented as needed).  They are not distinguished explicitly on the wire: applications agree out-of-band about when to use what, much like Protobuf, Thrift, etc.

| Name                   | JSON Encoding                                                            |
| ---------------------- | ------------------------------------------------------------------------ |
| `null`                 | Null                                                                     |
| `bool`                 | Boolean                                                                  |
| `list`/`…s`            | Array                                                                    |
| `array`                | Array                                                                    |
| `map`                  | Object                                                                   |
| `variant`/`enum`       | Array[`string`,args…] / `string` with first or all letters uppercased    |
| `struct`/`obj`         | Object with field name keys                                              |
| `series`               | Array[`struct`,...]                                                      |
| `collection`/`heap`    | `map` of `enum` keys to `list[struct,...]` or `series` (same in JSON)    |
| `string`/`str`         | String (necessarily UTF-8)                                               |
| `bytes`/`data`         | String Base64-URL                                                        |
| `decimal`/`dec`        | String: optional `-`, then 1+ digits, then possibly `.` and 1+ digits    |
| `uint`                 | Number within JS `MAX_SAFE_INTEGER`, `decimal` otherwise                 |
| `int`                  | Number within JS `MIN/MAX_SAFE_INTEGER`, `decimal` otherwise             |
| `ratio`                | String: optional `-`, 1+ digits, `/`, 1+ digits                          |
| `percent`/`pct`        | String: `decimal` hundredths + '%' (i.e. 50% is "50%")                   |
| `float32,64`           | Number                                                                   |
| `mask`                 | `list` of a mix of `string` and `list` (see below)                       |
| `date`/`_on`           | `uint` as YYYYMMDD (see below)                                           |
| `datetime`/`time`      | `uint` as YYYYMMDDHHMM (see below)                                       |
| `timestamp`/`ts`/`_at` | `int` seconds since UNIX Epoch `- 1,750,750,750`                         |
| `timespan`/`span`      | `list` of three `int` (see below)                                        |
| `id`/`guid`/`uuid`     | `uint` or `string` depending on source type                              |
| `code`                 | `string` strictly `[A-Z0-9_]` (i.e. "USD")                               |
| `language`/`lang`      | `code` IETF BCP-47                                                       |
| `country`/`cntry`      | `code` ISO 3166-1 alpha-2                                                |
| `region`/`rgn`         | `code` ISO 3166-2 alpha-1/3 (without country prefix)                     |
| `currency`/`curr`      | `code` ISO 4217 alpha-3                                                  |
| `tax_code`             | `code` "CC[_RRR]_X": ISO 3166-1, ISO 3166-2, acronym                     |
| `unit`                 | `code` UN/CEFACT Recommendation 20 unit of measure                       |
| `text`                 | `map` of `lang,string` pairs / `string` for just one in a clear context  |
| `amount`/`price`/`amt` | String: `decimal` and optionally space + `currency` (i.e. "1.23 CAD")    |
| `tax`/`tax_amt`        | String: `decimal`, optional space + `currency`, mandatory space + `tax_code` |
| `quantity`/`qty`       | String: `decimal` and optionally space a `unit` (i.e. "1.23 GRM")        |
| `ip`                   | `string` IPv4 or IPv6 notation                                           |
| `subnet`/`cidr`/`net`  | `string` CIDR notation                                                   |
| `coords`/`latlong`     | `list[decimal,decimal]` as WGS84 coordinates                             |

## Canonical Encoding

* When possible, Objects should be sorted by ascending key when buffering the whole list is possible, to facilitate compression.

* Number, `decimal` and `ratio` must strip leading zeros and trailing decimal zeros.

* Floating point numbers must be represented in the smallest form which does not lose precision.  Note that `-0.0` and `+0.0` are _not_ considered equivalent, however all `NaN` bit patterns are considered equal.  When converting between precisions, denormalized numbers should be normalized if the target precision can represent the exact value as a normal number.  This ensures minimal representation while maintaining precision.

## Additional Notes on Types

### Collection

Standard pattern for grouping related objects by type, eliminating redundancy.  Facilitates the use of normalizing references by ID.  The root map's `enum` is application-defined to represent object classes ("User", "Order", etc.).  The contained lists of objects should include ID fields.  Combined with our canonical encoding, this helps payloads be as small and easy to compress as possible.

For example, instead of embedding related users and products in an order object into a tree where some products may be duplicated, create a collection where each item (users, products, orders) is present exactly once and refer to each other by ID.

### Date, Datetime

Calendar and wall clock time.  Time zone is outside the scope of this type, derived from context as necessary.  Their `uint` format is a compromise between size and readability.

## Timespan

Calendar duration expressed as half-months, days and seconds, each signed and applied in three steps in that order when it is used.  For example, "one year minus one day" would be `[24,-1,0]`.

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

### User-Defined Types

Tags are represented in JSON as objects with a single member whose key is a string starting with "@" followed by a number 0..63, with the value being the tagged value. For example, a user-defined "URL" type could be decided as `{"@0": "https://example.com"}`. Such tags may have completely different meanings across different applications, so their use makes the resulting data non-portable. Decoders should fail when presented with unknown tags.

## Implementation Considerations

### String Validation

Since strings are expected to be valid UTF-8, encoders and decoders should fail when presented with invalid UTF-8.

### Decoding Security

Implementations should consider reasonable limits on:

* Total nesting depth (128 might be reasonable)
* Maximum string length (1MB to 1GB might be reasonable)
* Maximum number of object members (1K might be reasonable)
