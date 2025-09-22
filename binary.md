# Vanilla Object Format — Binary

## WIRE FORMAT

A Vanilla Object Format chunk is a stream of values, each sometimes followed by data as specified by the value itself.

Optionally, writers may prefix their output with Tag 5505 applied to Int 79, which encodes to `0xFF81564F` (the last 2 bytes spelling ASCII "VO").  This tag-value combination is reserved as a format magic number when used at position zero, to be discarded by readers.  This prefix should be used whenever VOF is used to store permanent data, such as in files or databases and may be omitted for ephemeral transactions.

The suggested MIME type for binary encoded transfers is `application/x-vanilla-object` while JSON remains `application/json`.

The suggested file name extension is `.vo`.

The choice to stream or assemble as a single chunk is left to developers based on their applications' needs.  The main use case for streaming would be for sending a large (>100) or unknown number of results to some query.

Decoders encountering impossible input (including invalid UTF-8 in `string` data) should discard the entire chunk and return an appropriate error.

### Control Values

Small integers are compressed at the slight expense of larger ones similarly to the Prefix Varint format (itself a variation on LEB128 and VLQ which eliminates loops, most shifts and represents 64 bits in 9 bytes instead of 10).  Extra bytes for the multi-byte integers are in Little Endian order, so any bits in the initial byte are the least significant.  Illustrated here from the decoder point of view, we see that very little computing is involved:

| Byte (`c`) | Type               | Condition | Description / Operation                                  |
| ---------- | ------------------ | --------- | -------------------------------------------------------- |
| `0_______` | Int 7-bit          | `< 128`   | `c`                                                      |
| `10______` | Int 14-bit         | `< 192`   | `(next_byte() << 6) + c - 128`                           |
| `110_____` | Int 21-bit         | `< 224`   | `(next_bytes_le(2) << 5) + c - 192`                      |
| `111000__` | Int 26-bit         | `< 228`   | `(next_bytes_le(3) << 2) + c - 224`                      |
|            | Int 32,40,48,56,64 | `< 233`   | Next 4,5,6,7,8 bytes are int Little Endian               |
|            | Float 32,64        | `< 235`   | Next 4,8 bytes are IEEE 754 Little Endian                |
|            | Null               | `== 235`  |                                                          |
|            | String             | `== 236`  | Next is size in bytes, then UTF-8 bytes                  |
|            | Struct Open        | `== 237`  | Open (groups until Close, defined below)                 |
|            | List Open          | `== 238`  | Values until `List Close`                                |
|            | List Close         | `== 239`  | Close nearest `List Open`                                |
|            | List               | `< 249`   | Exactly 0..8 items                                       |
|            | Data               | `== 249`  | Next is size in bytes, then raw bytes                    |
|            | Reserved           | `< 255`   | Next is size in bytes, then raw bytes                    |
|            | Tag                |           | Next value is Int qualifier, then qualified value        |

### Canonical Encoding

* Integers must be encoded in the smallest form possible.

* Floating point numbers must be represented in the smallest form which does not lose precision.  Note that `-0.0` and `+0.0` are _not_ considered equivalent, however all `NaN` bit patterns are considered equal.  When converting between precisions, denormalized numbers should be normalized if the target precision can represent the exact value as a normal number.  This ensures minimal representation while maintaining precision.

* Lists used as maps (odd keys, even values) should be sorted by ascending key when buffering the whole list is possible, to facilitate compression.

* Lists of 0..8 items must be encoded with the short forms 240..248.  Thus maps of 0..4 pairs must be encoded as 242, 244, 246, 248.

### Implicit List

A chunk is always considered a list without the need for an initial `List Open` nor a final `Close`.  Therefore, a 7-bit ASCII file is a valid list of small integers.

### Int Optionally Signed

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

## DATA TYPES

These higher-level types are standard (to be preferred to alternatives) but optional (implemented as needed).  They are not distinguished explicitly on the wire: applications agree out-of-band about when to use what, much like Protobuf, Thrift, etc.  Encoders _may_ elect to tag values in situations where the encoded data must be decoded without a schema, but it is not the primary goal of this format.  (Our JSON encoding is much more self-describing in that regard.)

| Tag  | Name                   | Wire Encoding                                                |
| ---- | ---------------------- | ------------------------------------------------------------ |
| 64   | `null`                 | Null                                                         |
| 65   | `bool`                 | False: Int 0 / True: Int 1                                   |
| 66   | `list`/`…s`            | List(0..10) + 0..10 vals / List Open + vals + Close          |
| 67   | `map`                  | `list` of alternating keys and values                        |
| 68   | `variant`/`enum`       | `list[Int,args…]` / `Int`                                    |
| 69   | `struct`/`obj`         | Struct Open + groups + Struct Close                          |
| 70   | `collection`/`heap`    | `map` of `enum` keys to `map` of ID keys to `struct`         |
| 71   | `string`/`str`         | String + size + bytes as UTF-8                               |
| 72   | `bytes`/`data`         | Data + size + raw bytes                                      |
| 73   | `decimal`/`dec`        | Int as signed ("ZigZag") `<< 3` + 0..9 places (see below)    |
| 74   | `uint`                 | Int                                                          |
| 75   | `int`                  | Int signed ("ZigZag")                                        |
| 76   | `ratio`                | `list[int,uint]` where the denominator must not be zero      |
| 77   | `percent`/`pct`        | `decimal` rebased to 1 (i.e. 50% is 0.5)                     |
| 78   | `float32`              | Float 32                                                     |
| 79   | `float64`              | Float 64                                                     |
| 80   | `mask`                 | `list` of a mix of `uint` and `list` (recursive)             |
| 81   | `date`/`_on`           | `uint` (see below)                                           |
| 82   | `datetime`/`time`      | `uint` (see below)                                           |
| 83   | `timestamp`/`_ts`      | `int` seconds since UNIX Epoch `- 1,750,750,750`             |
| 84   | `timespan`/`span`      | `list` of three `int` (see below)                            |
| 85   | `id`/`guid`/`uuid`     | `uint` or `string` depending on source type                  |
| 86   | `code`                 | `string` strictly `[A-Z0-9_]` (i.e. "USD")                   |
| 87   | `language`/`lang`      | `code` IETF BCP-47                                           |
| 88   | `country`/`cntry`      | `code` ISO 3166-1 alpha-2                                    |
| 89   | `region`/`rgn`         | `code` ISO 3166-2 alpha-1/3 (without country prefix)         |
| 90   | `currency`/`curr`      | `code` ISO 4217 alpha-3                                      |
| 91   | `tax_code`             | `code` "CC[_RRR]_X": ISO 3166-1, ISO 3166-2, acronym         |
| 92   | `unit`                 | `code` UN/CEFACT Recommendation 20 unit of measure           |
| 93   | `text`                 | `map` of `lang,string` pairs / `string` for just one in a clear context |
| 94   | `amount`/`price`/`amt` | `list[decimal,currency]` / `decimal`                         |
| 95   | `tax`/`tax_amt`        | `list[decimal,tax_code,currency]` / `list[decimal,tax_code]` |
| 96   | `quantity`/`qty`       | `list[decimal,unit]` / `decimal`                             |
| 97   | `ip`                   | `bytes` with 4 or 16 bytes (IPv4 or IPv6)                    |
| 98   | `subnet`/`cidr`/`net`  | `list[ip,uint]` CIDR notation: IP with netmask size in bits  |
| 99   | `coords`/`latlong`     | `list[decimal,decimal]` as WGS84 coordinates                 |

### Collection

Standard pattern for grouping related objects by type and then ID, eliminating redundancy.  Facilitates the use of normalizing references by ID.  The root map's `enum` is application-defined to represent object classes ("User", "Order", etc.).  The contained maps are keyed by whatever ID type each object class uses.  Combined with our canonical encoding, this helps payloads be as small and easy to compress as possible.

For example, instead of embedding related users and products in an order object into a tree where some products may be duplicated, create a collection where each item (users, products, orders) is present exactly once and refer to each other by ID.

### Decimal

A signed ("ZigZag") integer left-shifted 3 bits to make room for a 3-bit value representing 0, 1, 2, 3, 4, 5, 6 or 9 decimal places.  For example, -2.135 would be -2135 and 3 places, or `(4269 << 3) + 3 = 34155`, which would then be encoded as a 21-bit `Int` on the wire.

The canonical encoding is the smallest representation possible.  For example, 1.1 should be represented as "11 with 1 decimal place", not as "110 with 2 decimal places".

### Date

Calendar date, sortable.  Time zone is outside the scope of this type, derived from context as necessary.  Structured in 17 bits as `(year << 9) + (month << 5) + day` where:
* **year** — Number of years since 1900 (i.e. 2025 is 125)
* **month** — 1..12
* **day** — 1..31

### Datetime

Extends `Date` with wall clock time, still sortable and with implicit time zone.  Structured with minute precision in 28 bits as `(year << 20) + (month << 16) + (day << 11) + (hour << 6) + minute` where:
* **year** — Number of years since 1900 (i.e. 2025 is 125)
* **month** — 1..12
* **day** — 1..31
* **hour** — 0..23
* **minute** — 0..59

### Timespan

Calendar duration expressed as half-months, days and seconds, each signed and applied in three steps in that order when it is used.

### Text

If multiple strings are provided with the same language code, the first one wins.  Used in its bare `string` form, it is up to the applications to agree on the choice of default language.

The canonical encoding is to use the bare `string` form when a single language is used and corresponds to the default language (if one is defined), to minimize space.

### Mask

Compact equivalent to Protobuf's FieldMask.  In the context of a specific `struct` definition, an associated `mask` is a sorted `list` of field IDs where any field may be wrapped in a `list` in order to specify its child `struct`'s fields as well.  For example, fields 1, 2, 5, 6 where 5 is a sub-structure of which we want fields 2 and 3 only would be encoded as: `[1,2,[5,2,3],6]`.  Useful in RPC where a service may declare which fields are available or a client may request a limited subset of available data (similar to SQL `SELECT`, PostgREST's "Vertical Filtering" or GraphQL).

### User-Defined Types

Tags 0..63 are available for applications to define their own types from our basic types and 64+ are reserved.  For example, a user-defined "URL" type could be decided as Tag 0 followed by Data used as a `string`.  Obviously, this means that such tags may have completely different meanings across different applications, so their use makes the resulting data non-portable.  Decoders should fail when presented with unknown tags.

## Implementation Considerations

### Reserved Types

The 5 reserved control values are predetermined to use the same structure as `Data`: an unsigned number of bytes follows, and then as many bytes as specified.  This makes room for future types such as large integers or floats while guaranteeing that older decoders can safely skip over such unknown value types.

### Maps

Decoders should use the last value when a key is present multiple times.

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

* The `float16` type was omitted because it was deemed too rare.
* The `decimal`, `date` and `datetime` types were designed for financial systems based on SQLite and kept here for their compact sizes.
* The `code` type was initially designed as a base 37 `uint`, but the space savings were not worth the implementation complexity.
* The last size of `decimal` is 9 and not 7 in order to match the maximum precision allowed in some other business contexts such as ANSI X12.
* The `collection` type was favored vs low-level byte offset references, for simplicity.
* A single-group struct control value was abandoned early because it would've required backtracking in encoders.
