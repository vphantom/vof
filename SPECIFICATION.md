# Vanilla Object Format

## Data Types

These are standard (to be preferred to alternatives) but optional (implemented as needed).  They are not distinguished explicitly on the wire: applications agree out-of-band about when to use what, much like Protobuf, Thrift, etc.

| Name                   | Tag  | Binary Encoding                                              | JSON Encoding                                                |
| ---------------------- | ---- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| `null`                 | 64   | Null                                                         | Null                                                         |
| `bool`                 | 65   | False: Int 0 / True: Int 1                                   | Boolean                                                      |
| `list`/`…s`            | 66   | List(0..8) + 0..8 vals / List Open + vals + Close            | Array                                                        |
| `array`                | 67   | Array + dimcount + dim sizes... + values...                  | Array                                                        |
| `map`                  | 68   | `list` of alternating keys and values                        | Object                                                       |
| `variant`/`enum`       | 69   | `list[Int,values…]` / `Int`                                  | Array[String,values…] / String                               |
| `struct`/`obj`         | 70   | Struct Open + groups + Struct Close                          | Object w/ field name keys                                    |
| `series`               | 71   | Series + count + headers... + values... + Close              | Array[`struct`…]                                             |
| `collection`/`heap`    | 72   | `map` of `enum` keys to `list[struct…]` or `series`          | _same_                                                       |
| `string`/`str`         | 73   | String + size + bytes as UTF-8                               | String (necessarily UTF-8)                                   |
| `bytes`/`data`         | 74   | Data + size + raw bytes                                      | String base-64 URL encoded                                   |
| `uint`                 | 75   | Int                                                          | Number / `decimal`                                           |
| `int`/`sint`           | 76   | Int signed ("ZigZag", see below)                             | Number / `decimal`                                           |
| `decimal`/`dec`        | 77   | `sint << 3` + 0..9 places (see below)                        | String: optional `-` + 1+ digits + possibly `.` and 1+ digits |
| `ratio`                | 78   | `list[int,uint]`                                             | String: optional `-` + 1+ digits + `/` + `+ digits           |
| `percent`/`pct`        | 79   | `decimal` rebased to 1 (i.e. 50% is 0.5)                     | String: `decimal` hundredths + `%` (i.e. 50% is "50%")       |
| `float32`              | 80   | Float 32                                                     | Number                                                       |
| `float64`              | 81   | Float 64                                                     | Number                                                       |
| `mask`                 | 82   | `list` of a mix of `uint` and `list` (recursive)             | _same_                                                       |
| `date`/`_on`           | 83   | `uint` (see below)                                           | `uint` as YYYYMMDD (see below)                               |
| `datetime`/`time`      | 84   | `uint` (see below)                                           | `uint` as YYYYMMDDHHMM (see below)                           |
| `timestamp`/`_ts`      | 85   | `int` seconds since UNIX Epoch `- 1,750,750,750`             | _same_                                                       |
| `timespan`/`span`      | 86   | `list` of three `int` (see below)                            | _same_                                                       |
| `code`                 | 87   | `string` strictly `[A-Z0-9_]` (i.e. "USD")                   | _same_                                                       |
| `language`/`lang`      | 88   | `code` IETF BCP-47                                           | _same_                                                       |
| `country`/`cntry`      | 89   | `code` ISO 3166-1 alpha-2                                    | _same_                                                       |
| `region`/`rgn`         | 90   | `code` ISO 3166-2 alpha-1/3 (without country prefix)         | _same_                                                       |
| `currency`/`curr`      | 91   | `code` ISO 4217 alpha-3                                      | _same_                                                       |
| `tax_code`             | 92   | `code` "CC[_RRR]_X": ISO 3166-1, ISO 3166-2, acronym         | _same_                                                       |
| `unit`                 | 93   | `code` UN/CEFACT Recommendation 20 unit of measure           | _same_                                                       |
| `text`                 | 94   | `map` of `lang,string` pairs / `string` for just one         | _same_                                                       |
| `amount`/`price`/`amt` | 95   | `list[decimal,currency]` / `decimal`                         | String: `decimal` + optional space and `currency` (i.e. "1.23 CAD") |
| `tax`/`tax_amt`        | 96   | `list[decimal,tax_code,currency]` / `list[decimal,tax_code]` | String: `decimal` + optional space and `currency` + mandatory space + `tax_code` |
| `quantity`/`qty`       | 97   | `list[decimal,unit]` / `decimal`                             | String: `decimal` + optional space and `unit` (i.e. "1.23 GRM") |
| `ip`                   | 98   | `bytes` with 4 or 16 bytes (IPv4 or IPv6)                    | String: IPv4 or IPv6 notation                                |
| `subnet`/`cidr`/`net`  | 99   | `list[ip,uint]` CIDR notation: IP with netmask bit size      | String: CIDR notation                                        |
| `coords`/`latlong`     | 100  | `list[decimal,decimal]` as WGS84 coordinates                 | _same_                                                       |

### Variant / Enum

Identifiers are unsigned integers (binary) and strings (JSON) with their first or all letters uppercase.

### Struct

Similar to Protobuf's messages, their field numbers and names should remain reserved forever when they are deprecated to avoid version conflicts.  Field names must begin with a lowercase letter.

### Collection

Standard pattern for grouping related objects by type, eliminating redundancy.  Facilitates the use of normalizing references by ID.  The root map's `enum` is application-defined to represent object classes ("User", "Order", etc.).  The contained lists of objects should include ID fields.  Combined with our canonical encoding, this helps payloads be as small and easy to compress as possible.

For example, instead of embedding related users and products in an order object into a tree where some products may be duplicated, create a collection where each item (users, products, orders) is present exactly once and refer to each other by ID.

### Decimal

In binary encoding, this is a signed ("ZigZag") integer left-shifted 3 bits to make room for a 3-bit value representing 0, 1, 2, 3, 4, 5, 6 or 9 decimal places.  For example, -2.135 would be -2135 and 3 places, or `(4269 << 3) + 3 = 34155`, which would then be encoded as a 21-bit `Int` on the wire.

### Date

Calendar date, sortable.  Time zone is outside the scope of this type, derived from context as necessary.

In binary encoding, it is structured in 17 bits as `(year << 9) + (month << 5) + day` where:
* **year** — Number of years since 1900 (i.e. 2025 is 125)
* **month** — 1..12
* **day** — 1..31

### Datetime

Extends `date` with wall clock time, still sortable and with implicit time zone.

In binary encoding, it is structured with minute precision in 28 bits as `(year << 20) + (month << 16) + (day << 11) + (hour << 6) + minute` where:
* **year** — Number of years since 1900 (i.e. 2025 is 125)
* **month** — 1..12
* **day** — 1..31
* **hour** — 0..23
* **minute** — 0..59

### Timespan

Calendar duration expressed as half-months, days and seconds, each signed and applied in three steps in that order when it is used.  For example, "one year minus one day" would be `[24,-1,0]`.

### Text

If multiple strings are provided with the same language code, the first one wins.  Used in its bare `string` form, it is up to the applications to agree on the choice of default language.

The canonical encoding is to use the bare `string` form when a single language is used and corresponds to the default language (if one is defined), to minimize space.

### Mask

Equivalent to Protobuf's FieldMask.  In the context of a specific `struct` definition, an associated `mask` is a sorted `list` of field names where any field may be wrapped in a `list` in order to select its child `struct`'s fields as well.  For example, fields "id", "name", "user", "type" where "user" is a sub-structure of which we want field "country" only would be encoded as: `["id","name",["user","country"],"type"]`.  Useful in RPC where a service may declare which fields are available or a client may request a limited subset of available data (similar to SQL `SELECT`, PostgREST's "Vertical Filtering" or GraphQL).

In binary encoding, `uint` field IDs are used instead of field names.  For example, the same structure as above may be `[1,2,[5,2,3],6]`.

### Tagged Values

Tags 0..63 are available for applications to define their own types from our basic types and 64+ are reserved.  For example, a user-defined "URL" type could be decided as Tag 0 followed by a `string`.  Obviously, this means that such tags may have completely different meanings across different applications, so their use makes the resulting data non-portable.  Decoders should fail when presented with unknown tags.

In JSON, tags are represented as objects with a single member whose key is a string starting with "@" followed by a number 0..63, with the value being the tagged value. For example, a user-defined "URL" type could be decided as `{"@0": "https://example.com"}`.

Encoders may elect to tag values with standard types (tags 64+) in situations where the encoded data must be decoded without a schema, but it is not the primary goal of this format.

## JSON Encoding

The regular MIME type (`application/json`) for JSON encoded transfers is recommended.

### Canonical Encoding

* When possible, Objects should be sorted by ascending key when buffering the whole list is possible, to facilitate compression.

* Number, `decimal` and `ratio` must strip leading zeros and trailing decimal zeros.

* Integers must only encode as `decimal` when they are outside of JavaScript `MIN/MAX_SAFE_INTEGER` range.

## Binary Encoding

A Vanilla Object Format chunk is a stream of values, each sometimes followed by data as specified by the value itself.

Optionally, writers may prefix their output with Tag 5505 applied to Int 79, which encodes to `0xFF81564F` (the last 2 bytes spelling ASCII "VO").  This tag-value combination is reserved as a format magic number when used at position zero, to be discarded by readers.  This prefix should be used whenever VOF is used to store permanent data, such as in files or databases and may be omitted for ephemeral transactions.

The suggested MIME type for binary encoded transfers is `application/x-vanilla-object`.

The suggested file name extension is `.vo`.

The choice to stream or assemble as a single chunk is left to developers based on their applications' needs.  The main use case for streaming would be for sending a large (>100) or unknown number of results to some query.

Decoders encountering impossible input (including invalid UTF-8 in `string` data) should discard the entire chunk and return an appropriate error.

### Control Values

Small integers are compressed at the slight expense of larger ones similarly to the Prefix Varint format (itself a variation on LEB128 and VLQ which eliminates loops, most shifts and represents 64 bits in 9 bytes instead of 10).  Extra bytes for the multi-byte integers are in Little Endian order, so any bits in the initial byte are the least significant.  Illustrated here from the decoder point of view, we see that very little computing is involved:

| Byte (`c`) | Type               | Condition | Description / Operation                                 |
| ---------- | ------------------ | --------- | ------------------------------------------------------- |
| `0_______` | Int 7-bit          | `< 128`   | `c`                                                     |
| `10______` | Int 14-bit         | `< 192`   | `(next_byte() << 6) + c - 128`                          |
| `110_____` | Int 21-bit         | `< 224`   | `(next_bytes_le(2) << 5) + c - 192`                     |
| `111000__` | Int 26-bit         | `< 228`   | `(next_bytes_le(3) << 2) + c - 224`                     |
|            | Int 32,40,48,56,64 | `< 233`   | Next 4,5,6,7,8 bytes are int Little Endian              |
|            | Float 32,64        | `< 235`   | Next 4,8 bytes are IEEE 754 Little Endian               |
|            | Null               | `== 235`  |                                                         |
|            | String             | `== 236`  | Next is size in bytes, then as many UTF-8 bytes         |
|            | Struct Open        | `== 237`  | Open (groups until Close, defined below)                |
|            | List Open          | `== 238`  | Values until `List Close`                               |
|            | Close              | `== 239`  | Close nearest `List Open` or `Series`                   |
|            | List               | `< 249`   | Exactly 0..8 items                                      |
|            | Data               | `== 249`  | Next is size in bytes, then as many raw bytes           |
|            | Array              | `== 250`  | Next: dimcount, dims..., values... (see below)          |
|            | Series             | `== 251`  | Next: headcount, heads..., count, values... (see below) |
|            | _reserved_         | `< 255`   | Next is size in bytes, then as many raw bytes           |
|            | Tag                |           | Next value is Int qualifier, then qualified value       |

### Canonical Encoding

* Integers and `decimal` must be encoded in the smallest form possible.  For example, 1.1 should only be "11 with 1 decimal place."

* Floating point numbers must be represented in the smallest form which does not lose precision.  Note that `-0.0` and `+0.0` are _not_ considered equivalent, however all `NaN` bit patterns are considered equal.  When converting between precisions, denormalized numbers should be normalized if the target precision can represent the exact value as a normal number.  This ensures minimal representation while maintaining precision.

* Lists used as maps (odd keys, even values) should be sorted by ascending key when buffering the whole list is possible, to facilitate compression.

* Lists of 0..8 items must be encoded with the short forms 240..248.  Thus maps of 0..4 pairs must be encoded as 242, 244, 246, 248.

### Implicit List

A chunk is always considered a list without the need for an initial `List Open` nor a final `Close`.  Therefore, a 7-bit ASCII file is a valid list of small integers.

### Array

Fixed-size multi-dimensional lists.  Following the control character is an `Int` specifying how many dimensions there are, followed by as many `Int` as specified.  Each value is then added from zero-index onwards, as many values as the product of all dimensions.

For example, a 3D array of 2x2x2 could be: 250, 3, 2, 2, 2, 1, 2, 3, 4, 5, 6, 7, 8

### Negative Integers

When an integer is considered signed, its least significant bit before encoding into the above indicates the sign.  Encoding from typical 2's complement is `(i >> (int_size - 1)) XOR (i << 1)` and decoding is `(value >> 1) XOR -(value AND 1)`.  This is identical to Protbuf's "ZigZag" encoding.

### Struct

Similar to Protobuf's messages, their fields are numbered from 0.  Structs are groups of values, each structured as a field identification byte followed by as many values as the byte specifies.  Fields must thus be encoded in ascending numeric order.

Within a struct (after a `Struct Open` control byte), fields are organized into groups for efficiency. Each group begins with a control byte that indicates which fields are present:

* Gap: under 128 is the number of fields to skip after the last field ID, which will be followed by a single value.
* Struct Close: value 128 closes the nearest `Struct Open`.
* Field Map: over 128, the least significant 7 bits form a bitmap indicating which of the next 7 next field IDs (relative to the last) are present, followed by as many values as the bitmap has 1 bits set.

Example control bytes:
* `00000010` (2) means skip 2 field IDs (i.e. if the last field ID was 3, we now encode ID 6)
* `11100000` (224) means fields at positions +0, +1 are present, but +2 through +6 are absent
* `10000001` (129) means fields at positions +0, +6 are present, but +1 through +5 are absent

Note that field numbers and names should remain reserved forever when they are deprecated to avoid version conflicts in your schemas.

### Series

List of `Struct` where all the same fields are defined (typical in time series data, product price lists, etc.)  Following the control character is an `Int` specifying how many header control bytes there are, followed by as many such bytes as specified.  Each value of each `Struct` is then added, so this means the same value count for each instance.  The series is concluded with `Close`.

For example, a list of 3 objects each with fields 0,1,2 could be: 251, 1, 135, 3, 1, 1, 1, 2, 2, 2, 3, 3, 3

## Implementation Considerations

### Reserved Types

In binary encoding, the 3 reserved control values are predetermined to use the same structure as `Data`: an unsigned number of bytes follows, and then as many bytes as specified.  This makes room for future types such as large integers or floats while guaranteeing that older decoders can safely skip over such unknown value types.

### Maps

Decoders should use the last value when a key is present multiple times.

### Series

Encoders should use the first object of the list to determine the structure.  They should fail if a subsequent member has extra fields set.  If subsequent members are missing any fields though, encoders may encode Null instead of failing if they want to be permissive.

### Ratios

Encoders should fail if given zero as a denominator.

### Strings

Since strings are expected to be valid UTF-8, encoders and decoders should fail when presented with invalid UTF-8.

### Decoding Security

Implementations should consider reasonable limits on:

* Total nesting depth (128 might be reasonable)
* Maximum string length (1MB to 1GB might be reasonable)
* Maximum number of object members (1K might be reasonable)
* Maximum number of list elements (1M might be reasonable)
* Time to wait between values and/or overall rate limiting

Decoded data (and thus string) sizes must be checked for overflow: a corrupt or malicious size could extend well beyond the input.

## Design Compromises

* Types: `float16` was omitted because it was deemed too rare.
* Binary: the `decimal`, `date` and `datetime` types were designed for financial systems based on SQLite and kept here for their compact sizes.
* Binary: the `code` type was initially designed as a base 37 `uint`, but the space savings were not worth the implementation complexity.
* Binary: the last size of `decimal` is 9 and not 7 in order to match the maximum precision allowed in some other business contexts such as ANSI X12.
* Binary: the `collection` type was favored vs low-level byte offset references for simplicity.
* Binary: a single-group struct control value was abandoned early because it would've required backtracking in encoders.
