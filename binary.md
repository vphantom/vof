# Vanilla Object Format — Binary

## WIRE FORMAT

A Vanilla Object Format chunk is a stream of values, each sometimes followed by data as specified by the value itself.

Optionally, writers may prefix their output with Tag 649920 applied to Int 102, which encodes to `0xFFC0564F66` (the last 3 bytes spelling ASCII "VOf").  This tag-value combination is reserved as a format magic number when used at position zero, to be discarded by readers.  This prefix should be used whenever VOF is used to store permanent data, such as in files or databases and may be omitted for ephemeral transactions.

The suggested MIME type for binary encoded transfers is `application/x-vanilla-object` while JSON remains `application/json`.

The suggested file name extension is `.vof`.

The choice to stream or assemble as a single chunk is left to developers based on their applications' needs.  The main use case for streaming would be for sending a large (>100) or unknown number of results to some query.

Decoders encountering impossible input (including invalid UTF-8 in `string` data) should discard the entire chunk and return an appropriate error.

### Control Values

Small integers are compressed at the slight expense of larger ones similarly to the Prefix Varint format (itself a variation on LEB128 and VLQ which eliminates loops, most shifts and represents 64 bits in 9 bytes instead of 10).  Extra bytes for the multi-byte integers are in Little Endian order, so any bits in the initial byte are the least significant.  Illustrated here from the decoder point of view, we see that very little computing is involved:

| Byte (`c`) | Type                       | Condition | Description / Operation                                   |
| ---------- | -------------------------- | --------- | --------------------------------------------------------- |
| `0_______` | Int 7-bit                  | `< 128`   | `c`                                                       |
| `10______` | Int 14-bit                 | `< 192`   | `(next_byte() << 6) + c - 128`                            |
| `110_____` | Int 21-bit                 | `< 224`   | `(next_bytes_le(2) << 5) + c - 192`                       |
| `111000__` | Int 26-bit                 | `< 228`   | `(next_bytes_le(3) << 2) + c - 224`                       |
|            | Int 32,40,48,56,64,128,256 | `< 235`   | Next 4,5,6,7,8,16,32 bytes are int Little Endian          |
|            | Float 16,32,64,128,256     | `< 240`   | Next 2,4,8,16,32 bytes are IEEE 754 floating point binary |
|            | List                       | `== 240`  | Open (items until End)                                    |
|            | List                       | `== 241`  | Close nearest `List Open`                                 |
|            | List                       | `< 251`   | Exactly 0..8 items                                        |
|            | Struct                     | `== 251`  | Open (groups until Close, defined below)                  |
|            | Struct                     | `== 252`  | Open single group                                         |
|            | Data                       | `== 253`  | Next value is size in bytes, then as many bytes follow    |
|            | Null                       | `== 254`  |                                                           |
|            | Tag                        |           | Next value is Int qualifier, then qualified value         |

### Canonical Encoding

* Integers must be encoded in the smallest form possible.  Note that 128 and 256 bit integer support is not expected under normal circumstances and should only be used when readers are expected to support them.

* Lists of 0..8 items must be encoded with the short forms 242..250.  Thus maps of 0..4 pairs must be encoded as 242, 244, 246, 248, 250.  Open lists and maps have no maximum length.

* Lists used as key-value sequences (odd keys, even values) should be sorted by ascending key when buffering the whole list is possible, to facilitate higher-level compression.

* Structs without content must be encoded as an empty List (242).

* Structs with contiguous fields starting from 0 must be encoded as a List.

* Structs with a single group (largest field ID < 8) must be encoded with the shortcut (252).

* Floating point numbers must be represented in the smallest form which does not lose precision.  Note that `-0.0` and `+0.0` are _not_ considered equivalent, however all `NaN` bit patterns are considered equal.  When converting between precisions, denormalized numbers should be normalized if the target precision can represent the exact value as a normal number.  This ensures minimal representation while maintaining precision.  Note that 128 and 256 bit floating point support is not expected under normal circumstances and should only be used when readers are expected to support them.

### Implicit List

A chunk is always considered a list without the need for an initial `List Open` nor a final `Close`.  Therefore, a 7-bit ASCII file is a valid list of small integers.

### Int Optionally Signed

When an integer is considered signed, its least significant bit before encoding into the above indicates the sign.  Encoding from typical 2's complement is `(i >> (int_size - 1)) XOR (i << 1)` and decoding is `(value >> 1) XOR -(value AND 1)`.  This is identical to Protbuf's "ZigZag" encoding.

### Struct

Similar to Protobuf's messages, their fields are numbered from 0.  Structs are groups of values, each structured as a field identification byte followed by as many values as the byte specifies.  Fields must thus be encoded in ascending numeric order.  The initial implied previous field ID is -1, so the Delta of an initial field 0 is 0.

Within a struct (after a `Struct Open` or `Struct Open Single` control byte), fields are organized into groups for efficiency. Each group begins with a control byte that indicates which fields are present:

* If the byte is < 128, it represents a delta to add to the last field ID to get the current one, which will be followed by a single value.
* If the byte is 128, it marks the end of the nearest `Struct Open`, a `Struct Close`.
* If the byte is > 128, its least significant 7 bits form a bitmap indicating which of the next 7 next field IDs (relative to the last) are present, followed by as many values as the bitmap has 1 bits set.

For example:
* `11100000` (224) means fields at positions +0, +1 are present, but +2 through +6 are absent
* `10000001` (129) means fields at positions +0, +6 are present, but +1 through +5 are absent

Note that field numbers and names should remain reserved forever when they are deprecated to avoid version conflicts in your schemas.

## DATA TYPES

These higher-level types are standard (to be preferred to alternatives) but optional (implemented as needed).  They are not distinguished explicitly on the wire: applications agree out-of-band about when to use what, much like Protobuf, Thrift, etc.

| Name                   | Wire Encoding                                                         |
| ---------------------- | --------------------------------------------------------------------- |
| `null`                 | Null                                                                  |
| `bool`                 | Int values `0` and `1`                                                |
| `list`/`…s`            | List(0..8) + 0..8 vals / List Open + vals + Close                     |
| `map`                  | `list` of alternating keys and values                                 |
| `enum`                 | Int                                                                   |
| `variant`              | `list[enum,args…]` / `enum`                                           |
| `struct`/`obj`         | List(0..8) + values / Struct(0..8) + groups / Struct + groups + Close |
| `string`/`str`         | Data (empty) / Data + size + bytes as UTF-8                           |
| `bytes`/`data`         | Same as `string` but without implied UTF-8                            |
| `decimal`/`dec`        | Int as signed ("ZigZag") digits `<< 4` + 0..15 decimal places         |
| `uint`                 | Int                                                                   |
| `int`                  | Int signed ("ZigZag")                                                 |
| `ratio`                | `list[int,uint]` where the denominator must not be zero               |
| `percent`/`pct`        | `decimal` rebased to 1 (i.e. 50% is 0.5)                              |
| `float16`/`f16`        | Float 16 (Little Endian)                                              |
| `float32`/`f32`        | Float 32 (Little Endian)                                              |
| `float64`/`f64`        | Float 64 (Little Endian)                                              |
| `float128`/`f128`      | Float 128 (Little Endian)                                             |
| `float256`/`f256`      | Float 256 (Little Endian)                                             |
| `mask`                 | `list` of a mix of `uint` and `list` (recursive)                      |
| `datetime`/`date`/`dt` | Struct of up to 7 fields (see Datetime)                               |
| `timestamp`/`ts`       | `int` seconds since UNIX Epoch `- 1_677_283_200`                      |
| `id`/`guid`/`uuid`     | `uint` or `string` depending on source type                           |
| `code`                 | `int` interpreted as base-36                                          |
| `language`/`lang`      | `code` IETF BCP-47                                                    |
| `country`/`cntry`      | `code` ISO 3166-1 alpha-2                                             |
| `region`/`rgn`         | `code` ISO 3166-2 alpha-1/3 (without country prefix)                  |
| `currency`/`curr`      | `code` ISO 4217 alpha-3                                               |
| `unit`                 | `code` UN/CEFACT Recommendation 20 unit of measure                    |
| `text`                 | `map` of `lang,string` pairs / `string`                               |
| `amount`/`price`/`amt` | `list[decimal,currency]` / `decimal`                                  |
| `quantity`/`qty`       | `list[decimal,unit]` / `decimal`                                      |
| `ip`                   | `bytes` with 4 or 16 bytes (IPv4 or IPv6)                             |
| `subnet`/`cidr`/`net`  | `list[ip,uint]` CIDR notation: IP with netmask size in bits           |

### Map

Maps should not provide multiple values for the same key.  Encoders must fail when presented with such source data.

### Decimal

A signed ("ZigZag") integer left-shifted 4 bits followed by an unsigned nibble representing 0..15 decimal places.  For example, -2.135 would be -2135 and 3 places, or `4269 << 4 + 3 = 68307`, which is then encoded as a 21-bit `int` on the wire.

The canonical encoding is the smallest representation possible.  For example, 1.1 should be represented as "11 with 1 decimal place", not as "110 with 2 decimal places" and such.

### Datetime

Calendar concept, thus subject to a time zone.  Intended to be specified in any precision such as simple dates or dates with times.  Zero values should be omitted.  Non-zero UTC offsets are important even with dates in order to calculate correct differences.  Fields:

* **0: year** `int` offset from 2023

* **1: month** `int` 1..12

* **2: day** `int` 1..31

* **3: hours** `int` 0..23

* **4: minutes** `int` 0..59

* **5: seconds** `int` 0..59

* **6: offset** `int` -720..+840 minutes from UTC

With its signed integers, this may also be used to represent time spans.  In that use case, `offset` must not be specified.  For example, "yesterday next year" could be represented as `{year:1,day:-1}`.  The offset from 2023 keeps year representations shorter for typical current-day applications.

### Timestamp

This is a regular UNIX timestamp in seconds since an Epoch, except it is represented as an "Offset Julian Day", derived from NASA's Truncated Julian Day but using 60,000 days instead of 40,000. This means an offset of 1,677,283,200 seconds or 2023-02-25 00:00:00 UTC.  (This is "UNIX time", which does not include leap seconds, hence the 27 or 37 second offset from what you may expect.)

### Code

Codes are represented as a signed ("ZigZag") _positive_ integer, thus the maximum length of the string they represent is 11 characters.  The negative space is reserved for user-defined alternatives anywhere `code` is used (i.e. a custom language `FR` in the negative space would be distinct from positive `FR`, which is standard in IETF BCP-47).  While the use of custom codes is discouraged, this scheme makes it possible.

Caveat: this representation of codes, while compact, effectively strips leading zeros.  While this isn't a problem with the standards used here (for languages, units, etc.), it may be a problem with other uses, in which case a `string` is the safe choice.

Note on JSON interoperability: because codes are strings in JSON VOF, leading zeros would be preserved on the JSON side while being stripped on the binary side.  Therefore, standard and custom codes should never begin with leading zeros.

### Text

If multiple strings are provided with the same language code, the first one wins.  Used in its bare `string` form, it is up to the applications to agree on the choice of default language.

The canonical encoding is to use the bare `string` form when a single language is used and corresponds to the default language (if one is defined), to minimize space.

### Mask

Compact equivalent to Protobuf's FieldMask.  In the context of a specific `struct` definition, an associated `mask` is a sorted `list` of field IDs where any field may be wrapped in a `list` in order to specify its child `struct`'s fields as well.  For example, fields 1, 2, 5, 6 where 5 is a sub-structure of which we want fields 2 and 3 only would be encoded as: `[1,2,[5,2,3],6]`.  Useful in RPC where a service may declare which fields are available or a client may request a limited subset of available data (similar to SQL `SELECT`, PostgREST's "Vertical Filtering" or GraphQL).

### References

References at our level are much more efficient than an external compression scheme would be (i.e. gzip) because references let decoders reuse the same decoded resources, without having to expose a distinction between references by ID vs full inclusion at the application level.  This lets API designers include child objects uniformly in their schemas without worrying about redundancy in memory nor on the wire.

Encoders may note the output position of the `string` and `bytes` values encoded as they go.  When duplicates are encountered, they may be replaced with a `uint` of their original position (`0` being the first byte of the current buffer).  Decoders can similarly note positions as they go so they may reuse decoded data when they encounter a `uint` reference.

To keep implementations light and efficient, `struct` reference support is limited to the specific but highly useful scenario of structs with fields named `guid` or `uuid`. Those keys are considered globally unique, so when encoders encounter structs with the same IDs again, they may replace the duplicates with their unwrapped `guid` or `uuid` value (in that order of preference) which is a `uint` or `string` (Int or Data on the wire).  This is unambiguous since a `struct` is expected by decoders (a List or Struct on the wire).

For applications with table-specific ID namespaces, one strategy to benefit from references could be to fake GUIDs on the wire by prefixing a namespace to the ID in a `string`. For example, a single character followed by a Base-32 Crockford encoding of the ID could be readable yet short, such that "color 1234" might be "C16J", or "size 515" could be "SG3".  An equivalent `uint` strategy could be to left-shift the sequence by a fixed global number of bits (i.e. if the company has 11 types, maybe shift left by 4, allowing up to 16 types forever)

### User-Defined Types

Tags 0..63 are available for applications to define their own types from our basic types and 64+ are reserved.  For example, a user-defined "URL" type could be decided as Tag 0 followed by Data used as a `string`.  Obviously, this means that such tags may have completely different meanings across different applications, so their use makes the resulting data non-portable.  Decoders should fail when presented with unknown tags.

## Implementation Considerations

### Large Precision Numbers

Decoders without support for 128 or 256 bit integer or floating point numbers should fail when presented with such source data.

### Strings

Since strings are expected to be valid UTF-8, encoders and decoders should fail when presented with invalid UTF-8.

### Reference Tracking

The index of references maintained by decoders should use `string` keys (thus converting `uint` references to `string` ones) to avoid imposing a possible distinction between equivalent values of both types to encoders.

### Decoding Security

Implementations should consider reasonable limits on:

* Total nesting depth (128 might be reasonable)
* Maximum string length (1MB to 1GB might be reasonable)
* Maximum number of object members (1K might be reasonable)
* Time to wait between values and/or overall rate limiting

Decoded data (and thus string) sizes must be checked for overflow: a corrupt or malicious size could extend well beyond the input.

### Thread Safety

Buffered maps with sorted keys must by design be implemented in a single thread.  Reference tracking being global to entire chunks, must be implemented in a thread-safe structure.

Therefore, it is recommended to restrict encoding and decoding of specific chunks to a single thread to avoid these issues.
