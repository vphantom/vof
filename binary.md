# Vanilla Object Format — Binary

## WIRE FORMAT

A Vanilla Object Format chunk is a stream of values, each sometimes followed by data as specified by the value itself.

Optionally, writers may prefix their output with Tag 649920 applied to Int 102, which encodes to `0xFFC0564F66` (the last 3 bytes spelling ASCII "VOf").  This tag-value combination is reserved as a format magic number when used at position zero, to be discarded by readers.

The suggested MIME type for binary encoded transfers is `application/x-vanilla-object` while JSON remains `application/json`.

The suggested file name extension is `.vof`.

### Control Values

Small integers are compressed at the slight expense of larger ones similarly to Prefix Varint (a variation on LEB128 which eliminates loops, most shifts and represents 64 bits in 9 bytes instead of 10).  Extra bytes for the multi-byte integers are in Little Endian order, so any bits in the initial byte are the least significant.  Illustrated here from the decoder point of view, we see that very little work is involved:

| Byte (`c`) | Total Bytes | Type               | Condition | Description / Operation                                     |
| ---------- | ----------- | ------------------ | --------- | ----------------------------------------------------------- |
| `0_______` | 1           | Int 7-bit          | `< 128`   | `c`                                                         |
| `10______` | 2           | Int 14-bit         | `< 192`   | `(next_byte() << 6) + c - 128`                              |
| `110_____` | 3           | Int 21-bit         | `< 224`   | `(next_bytes_le(2) << 5) + c - 192`                         |
| `11100___` | 4           | Int 27-bit         | `< 232`   | `(next_bytes_le(3) << 3) + c - 224`                         |
|            | 5,6,7,8,9   | Int 32,40,48,56,64 | `< 237`   | `next_bytes_le(4)`, 5, 6, 7, 8                              |
|            | 1           | List               | `< 243`   | Open (items until End), End, exactly 0,1,2,3 items          |
|            | 1           | Struct             | `< 249`   | Open (groups until 128), empty, `01`, `001`, `011`, 1 group |
|            | _varies_    | Data               | `< 251`   | Size + bytes, empty                                         |
|            | 2,4,8       | Float              | `< 254`   | IEEE 754 floating point binary 16,32,64 bit precisions      |
|            | 1           | Null               | `== 254`  |                                                             |
|            | 1+V1+V2     | Tag                |           | V1 int qualifies V2, 0..63 user-defined, 64+ reserved       |

### Canonical Encoding

* Integers must be encoded in the smallest form possible.

* Lists of 0, 1, 2 or 3 items must be encoded with the short forms 239, 240, 241, 242.

* Lists used as key-value sequences (odd keys, even values) should sort by ascending key when buffering the whole list is possible.

* Structs without content must be encoded in short form 244.

* Structs with fields 0, 0,1 or 0,1,2 must be encoded as a List in short form (240, 241, 242).

* Structs with fields 1, 2 or 1,2 must be encoded with the shortcuts (245, 246, 247).

* Structs with a single group must be encoded with the shortcut (248), multiple groups with the general case (243) which is terminated by 128 (see Struct below).

* Empty Data must be encoded with the shortcut (250).  Other sizes use the general case (249) followed by an Int to specify the length, then the data bytes.

* Float 16, Float 32 and Float 64 are considered distinct types and thus canonical encoding does not require contracting larger precision floats into the smallest lossless precision.  This was decided to keep implementation complexity lower.

### Implicit List

A chunk is considered an implicit list without the initial `List Open` nor the final `Close` values.  Therefore, a 7-bit ASCII file is a valid list of integers.

### Int Optionally Signed

When an integer is considered signed, its least significant bit before encoding into the above indicates the sign.  Encoding from typical 2's complement is `(i >> (int_size - 1)) XOR (i << 1)` and decoding is `(value >> 1) XOR -(value AND 1)`.  This is identical to Protbuf's "ZigZag" encoding.

### Struct

Similar to Protobuf's messages, their fields are numbered from 0.  Structs are groups of values, each structured as a field identification byte followed by as many values as the byte specifies.  Fields must thus be encoded in ascending numeric order.  The initial implied previous field ID is -1, so the Delta of an initial field 0 is 0.

| Byte       | Condition | Description                                                   |
| ---------- | --------- | ------------------------------------------------------------- |
| `0_______` | `< 128`   | Delta (1..128) from previous field ID, 1 value follows        |
| `10000000` | `== 128`  | Close nearest `Struct Open`                                   |
| `1_______` |           | The 7 low bits map the next fields, 1 value per 1 bit follows |

Field numbers and names should remain reserved forever when they are deprecated to avoid version conflicts.

## DATA TYPES

These higher-level types are standard (to be preferred to alternatives) but optional (implemented as needed).  They are not distinguished explicitly on the wire: applications agree out-of-band about when to use what, much like Protobuf, Thrift, etc.

| Name                   | Wire Encoding                                                         |
| ---------------------- | --------------------------------------------------------------------- |
| `undefined`            | In a `struct`, the absence of a field                                 |
| `null`                 | Null                                                                  |
| `list`/`…s`            | List(0..3) + 0..3 vals / List Open + vals + Close                     |
| `map`                  | `list` of alternating keys and values                                 |
| `struct`/`obj`         | List(1..3) + values / Struct(0..3) + groups / Struct + groups + Close |
| `string`/`str`         | Data(0,2,4,8) + 0,2,4,8 bytes / Data + V + N bytes as UTF-8           |
| `bytes`/`data`         | Same as `string` but without implied UTF-8                            |
| `bool`                 | Int values `0` and `1`                                                |
| `uint`                 | Int                                                                   |
| `int`                  | Int signed ("ZigZag")                                                 |
| `float16`/`f16`        | Float 16                                                              |
| `float32`/`f32`        | Float 32                                                              |
| `float64`/`f64`        | Float 64                                                              |
| `enum`                 | `uint`                                                                |
| `variant`              | `list[uint,args…]` / `uint`                                           |
| `id`/`guid`/`uuid`     | `uint` or `string` depending on source type                           |
| `code`                 | `uint` interpreted as base-36 up to 12 chars (i.e. "USD" is `0x9BDD`) |
| `decimal`/`dec`        | `uint` as signed digits `<< 4` and 0..15 decimal places               |
| `ratio`                | `list[int,uint]`                                                      |
| `percent`/`pct`        | `decimal` rebased to 1 (i.e. 50% is 0.5)                              |
| `mask`                 | `list` of a mix of `uint` and `list` (recursive)                      |
| `datetime`/`date`/`dt` | Struct of up to 7 fields (see Datetime)                               |
| `timestamp`/`ts`       | `int` seconds since UNIX Epoch `- 1_677_283_227`                      |
| `language`/`lang`      | `code` IETF BCP-47                                                    |
| `country`/`cntry`      | `code` ISO 3166-1 alpha-2                                             |
| `region`/`rgn`         | `code` ISO 3166-2 alpha-1/3 (no country prefix)                       |
| `currency`/`curr`      | `code` ISO 4217 alpha-3                                               |
| `unit`                 | `code` UN/CEFACT Recommendation 20 unit of measure                    |
| `text`                 | `map` of `lang,string` pairs / `string`                               |
| `amount`/`amt`         | `list[decimal,currency]` / `decimal`                                  |
| `quantity`/`qty`       | `list[decimal,unit]` / `decimal`                                      |
| `ip`                   | `bytes` with 4 or 16 bytes (IPv4 or IPv6)                             |
| `subnet`/`cidr`/`net`  | `list[ip,uint]` CIDR notation: IP with netmask size in bits           |

### Datetime

Calendar concept, thus subject to a time zone.  Intended to be specified in any precision such as simple dates or dates with times.  Zero values may be omitted.  Non-zero UTC offsets are important even with mere dates.  Fields:

* **0: year** `int` offset from 2023

* **1: month** `uint` 1..12

* **2: day** `uint` 1..31

* **3: hours** `uint` 0..23

* **4: minutes** `uint` 0..59

* **5: seconds** `uint` 0..59

* **6: offset** `int` -720..+840 minutes from UTC

### Mask

Compact equivalent to Protobuf's FieldMask.  In the context of a specific `struct` definition, an associated `mask` is a sorted `list` of field IDs where any field may be wrapped in a `list` in order to specify its child `struct`'s fields as well.  For example, fields 1, 2, 5, 6 where 5 is a sub-structure of which we want field 2 only would be encoded as: `[1,2,[5,2],6]`.  Useful in RPC where a service may declare which fields are available or a client may request a limited subset of available data (similar to SQL `SELECT`, PostgREST's "Vertical Filtering" or GraphQL).

### References

References at our level are much more efficient than an external compression scheme would be (i.e. gzip) because references let decoders reuse the same decoded resources, without having to expose a distinction between references by ID vs full inclusion at the application level.  This lets API designers include child objects uniformly in their schemas without worrying about redundancy in memory nor on the wire.

Encoders may note the output position of the `string` and `bytes` values encoded as they go.  When duplicates are encountered, they may be replaced with a `uint` of their original position (`0` being the first byte of the current buffer).  Decoders can similarly note positions as they go so they may reuse decoded data when they encounter a `uint` reference.

To keep implementations light and efficient, `struct` reference support is limited to the specific but highly useful scenario of structs with fields named `guid` or `uuid`. Those keys are considered globally unique, so when encoders encounter structs with the same IDs again, they may replace the duplicates with their unwrapped `guid` or `uuid` value (in that order of preference) which is a `uint` or `string` (Int or Data on the wire).  This is unambiguous since a `struct` is expected by decoders (a List or Struct on the wire).

For applications with table-specific ID namespaces, one strategy to benefit from references could be to fake GUIDs on the wire by prefixing a namespace to the ID in a `string`. For example, a single character followed by a Base-32 Crockford encoding of the ID could be readable yet short, such that "color 1234" might be "C16J", or "size 515" could be "SG3".  An equivalent `uint` strategy could be to left-shift the sequence by a fixed global number of bits (i.e. if the company has 11 types, maybe shift left by 4, allowing up to 16 types forever)
