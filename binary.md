# Vanilla Object Format — Binary

## WIRE FORMAT

A Vanilla Object Format chunk is a stream of Varint control values, each sometimes followed by data as specified by the value itself.  Since some control values are constant and fit in a single byte, they may be identified without even decoding.

Optionally, writers may prefix their output with `0x21566F46` ("!VoF") as a format magic number.

The suggested MIME type for binary encoded transfers is `application/x-vanilla-object` while JSON remains `application/json`.

The suggested file name extension is `.vof`.

### Prefix Varint

Uses the same space as the better-known LEB128 (Protobuf, Thrift Compact), less for full 64 bits, while being nearly an order of magnitude faster to process.  The range of the first byte reveals the size.  This can be seen as accumulating LEB128 continuation bits into the first byte of a little-endian sequence.  Optimized for a maximum of 64 significant bits.  Illustrated from the decoding point of view:

| LSB        | Bytes | Precision | Condition | Operation                           |
| ---------- | ----- | --------- | --------- | ----------------------------------- |
| `0_______` | 1     | 7-bit     | `< 128`   | `c`                                 |
| `10______` | 2     | 14-bit    | `< 192`   | `(next_bytes_le(1) << 6) + c - 128` |
| `110_____` | 3     | 21-bit    | `< 224`   | `(next_bytes_le(2) << 5) + c - 192` |
| `1110____` | 4     | 28-bit    | `< 240`   | `(next_bytes_le(3) << 4) + c - 224` |
| `11110___` | 5     | 35-bit    | `< 248`   | `(next_bytes_le(4) << 3) + c - 240` |
| `111110__` | 6     | 42-bit    | `< 252`   | `(next_bytes_le(5) << 2) + c - 248` |
| `1111110_` | 7     | 49-bit    | `< 254`   | `(next_bytes_le(6) << 1) + c - 252` |
| `11111110` | 8     | 56-bit    | `== 254`  | `next_bytes_le(7)`                  |
| `11111111` | 9     | 64-bit    |           | `next_bytes_le(8)`                  |

### Zigzag signed

When an integer is considered signed, its least significant bit before encoding into the above indicates the sign.  Encoding from typical 2's complement is `(i >> (int_size - 1)) XOR (i << 1)` and decoding is `(value >> 1) XOR -(value AND 1)`.  This is identical to Protbuf's.

### Constants

These control bytes stand alone.  While they are technically constructed as a Prefix Varint, they don't need to be handled as such.  They are provided in their encoded, wire values here.

| Byte                        | Description                                  |
| --------------------------- | -------------------------------------------- |
| `0x01,05,09,0D,11,15,19,1D` | **List** of 0..7 values follows (`c >> 2`)   |
| `0x21`                      | **Null**                                     |
| `0x25`                      | **List** of values follows until **End**     |
| `0x29`                      | **End** of list                              |
| `0x2D,31`                   | **Tag** qualifies next value, reserved       |
| `0x35,39`                   | **Tag** qualifies next value, _user-defined_ |

### Variables

Any other byte is the first of a Prefix Varint sequence.  The 2 least significant bits of the decoded integer are used as follows:

| LSB  | Shift  | Remainder                                                             |
| ---- | ------ | --------------------------------------------------------------------- |
| `_0` | 1 bit  | **Int** (use Data when 63 bits isn't enough)                          |
| `01` | 2 bits | **Data** byte count of following data `+ 15` (i.e. 31 means 16 bytes) |
| `11` | 2 bits | **Bitmap** bitmap of up to 62 IDs followed by one value per set bit   |

## DATA TYPES

These higher-level types are standard (to be preferred to alternatives) but optional (implemented as needed).  They are not distinguished explicitly on the wire: applications agree out-of-band about when to use what, much like Protobuf, Thrift, etc.

| Name                   | Wire Encoding                                                               |
| ---------------------- | --------------------------------------------------------------------------- |
| `undefined`            | In a `struct`, the absence of a field                                       |
| `null`                 | Null                                                                        |
| `list`/`…s`            | List(0..7) + 0..7 vals / List + vals + End                                  |
| `map`                  | `list` of alternating keys and values, in ascending key order               |
| `string`/`str`         | Data + N bytes as UTF-8                                                     |
| `bytes`/`data`         | Data + N bytes                                                              |
| `bool`                 | Int values `0` and `1` (constant control bytes `0x01` and `0x05`)           |
| `uint`                 | Int / `bytes` little-endian for 64,128 bits                                 |
| `int`                  | `uint` Zigzag signed / `bytes` little-endian 2's complement for 64,128 bits |
| `enum`                 | `uint`                                                                      |
| `variant`              | `list[uint,args…]` / `uint`                                                 |
| `id`/`guid`/`uuid`     | `uint` or `string` depending on source type                                 |
| `code`                 | `uint` interpreted as base-36 up to 12 chars (i.e. "USD" is `0x9BDD`)       |
| `binary`/`float`/`fp`  | `bytes` as IEEE 754 float binary 16,32,64,128,256 precisions                |
| `decimal`/`dec`        | `uint` (Zigzag signed digits `<< 4`) + 0..15 decimal places                 |
| `ratio`                | Bitmap(0,1) + `int` numerator + `uint` denominator                          |
| `percent`/`pct`        | `decimal` rebased to 1 (i.e. 50% is 0.5)                                    |
| `struct`/`obj`         | Bitmap + vals / `map` with `uint` field ID keys / `uint` (see References)   |
| `ratio`                | `list[int,uint]`                                                            |
| `mask`                 | `list` of a mix of `uint` and `list` (recursive)                            |
| `datetime`/`date`/`dt` | `list` of 1..7 values (see Datetime)                                        |
| `timestamp`/`ts`       | `int` seconds since UNIX Epoch `- 1_677_283_227`                            |
| `language`/`lang`      | `code` IETF BCP-47                                                          |
| `country`/`cntry`      | `code` ISO 3166-1 alpha-2                                                   |
| `region`/`rgn`         | `code` ISO 3166-2 alpha-1/3 (no country prefix)                             |
| `currency`/`curr`      | `code` ISO 4217 alpha-3                                                     |
| `unit`                 | `code` UN/CEFACT Recommendation 20 unit of measure                          |
| `text`                 | `map` of `lang,string` pairs / `string`                                     |
| `amount`/`amt`         | `list[decimal,currency]` / `decimal`                                        |
| `quantity`/`qty`       | `list[decimal,unit]` / `decimal`                                            |
| `ip`                   | `bytes` with 4 or 16 bytes (IPv4 or IPv6)                                   |
| `subnet`/`cidr`/`net`  | `list[ip,uint]` CIDR notation: IP with netmask size in bits                 |

### Datetime

Calendar concept, thus subject to a time zone, represented as a List to facilitate truncating at any precision (i.e. just YMD). Items are, in order:

* Int year `- 2023`

* Uint month (1..12)

* Uint day (1..31)

* Uint hours (0..23)

* Uint minutes (0..59)

* Uint seconds (0..59)

* Int UTC offset in minutes (-720 .. +840)

### Struct

Similar to Protobuf's messages, their fields are named numbered from 0.  There are two encodings, in order of preference:

* `Bitmap` when `max(id) < 62 && ceil((2 + max(id)) / 7) < field_count`

* `map` of field IDs and their values

Field IDs and names should remain reserved forever when they are deprecated to avoid version conflicts.

### Mask

Compact equivalent to Protobuf's FieldMask.  In the context of a specific `struct` definition, an associated `mask` is a sorted `list` of field IDs where any field may be wrapped in a `list` in order to specify its child `struct`'s fields as well.  For example, fields 1, 2, 5, 6 where 5 is a sub-structure of which we want field 2 only would be encoded as: `[1,2,[5,2],6]`.  Useful in RPC where a service may declare which fields are available or a client may request a limited subset of available data (similar to SQL `SELECT`, PostgREST's "Vertical Filtering" or GraphQL).

### References

References at our level are much more efficient than an external compression scheme would be (i.e. gzip) because references let decoders reuse the same decoded resources, without having to expose a distinction between references by ID vs full inclusion at the application level.  This lets API designers include child objects uniformly in their schemas without worrying about redundancy in memory nor on the wire.

Encoders may note the output position of the `string` and `bytes` values encoded as they go.  When duplicates are encountered, they may be replaced with a `uint` of their original position (`0` being the first byte of the current buffer).  Decoders can similarly note positions as they go so they may reuse decoded data when they encounter a `uint` reference.

To keep implementations light and efficient, `struct` reference support is limited to the specific but highly useful scenario of fields named `guid` or `uuid`. Those keys are considered globally unique, so when encoders encounter the same IDs again they may replace duplicates with their unwrapped `guid` or `uuid` value (in that order of preference) which is `uint` or `string`.  This is unambiguous since a `struct` is expected by decoders.

For applications with table-specific ID namespaces, one strategy to benefit from references could be to fake GUIDs on the wire by prefixing a namespace to the ID in a `string`. For example, a single character followed by a Base-32 Crockford encoding of the ID could be readable yet short, such that "color 1234" might be "C16J", or "size 515" could be "SG3".  An equivalent `uint` strategy could be to left-shift the sequence by a fixed global number of bits (i.e. if the company has 11 types, maybe shift left by 4, allowing up to 16 types forever)
