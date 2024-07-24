# Vanilla Object Format — Binary

## WIRE FORMAT

A Vanilla Object Format chunk is a stream of values, each sometimes followed by data as specified by the value itself.

Optionally, writers may prefix their output with `0x566F461A` ("VoF^Z") as a format magic number.

The suggested MIME type for binary encoded transfers is `application/x-vanilla-object` while JSON remains `application/json`.

The suggested file name extension is `.vof`.

### Control Values

We compress small integers at the slight expense of larger ones, similarly to Prefix Varint (a variation on LEB128 which eliminates loops and most shifts).  Extra bytes for the multi-byte integers are in Little Endian order, so any bits in the initial byte are the least significant.  Non-integer types are in the highest values to minimize disruption for integers.  From the decoder point of view:

| 1st Byte (`c`) | Total Bytes | Type                | Condition | Description / Operation                               |
| -------------- | ----------- | ------------------- | --------- | ----------------------------------------------------- |
| `0_______`     | 1           | Int 7-bit           | `< 128`   | `c`                                                   |
| `10______`     | 2           | Int 14-bit          | `< 192`   | `(next_byte() << 6) + c - 128`                        |
| `110_____`     | 3           | Int 21-bit          | `< 224`   | `(next_bytes_le(2) << 5) + c - 192`                   |
| `11100___`     | 4           | Int 27-bit          | `< 232`   | `(next_bytes_le(3) << 3) + c - 224`                   |
| `111010__`     | 1           | List                | `< 236`   | Exactly `c - 232` items (0..3)                        |
| `111011__`     | 1           | Struct              | `< 240`   | Exactly `c - 236` groups (0..3)                       |
| `1111000_`     | 5           | Int 33-bit          | `< 242`   | `(next_bytes_le(4) << 1) + c - 240`                   |
|                | 1+V+N       | Data                | `== 242`  | Next `Int` V is size N in bytes                       |
|                | 1,3,5,9     | Data                | `< 247`   | Data (0,2,4,8 bytes)                                  |
|                | 6,7,8,9     | Int 40,48,56,64 bit | `< 251`   | `next_bytes_le(5)`, 6, 7, 8                           |
|                | 1           | List Open           | `== 251`  | Items until `List Close`                              |
|                | 1           | List Close          | `== 252`  | Close nearest `List Open`                             |
|                | 1           | Struct Open         | `== 253`  | Struct groups until `128` (see Struct)                |
|                | 1           | Null                | `== 254`  |                                                       |
|                | 1+V1+V2     | Tag                 |           | V1 int qualifies V2, 0..63 user-defined, 64+ reserved |

Lists of 0, 1, 2, 3 items, structs of 0, 1, 2, 3 groups and Data with 0, 2, 4, 8 bytes should be encoded in their short form.  Integers should be encoded in the smallest form possible.

### Implicit List

A chunk is considered an implicit list without the initial `List Open` nor the final `Close` values.  Therefore, a 7-bit ASCII file is a valid list of integers.

### Int Optionally Signed

When an integer is considered signed, its least significant bit before encoding into the above indicates the sign.  Encoding from typical 2's complement is `(i >> (int_size - 1)) XOR (i << 1)` and decoding is `(value >> 1) XOR -(value AND 1)`.  This is identical to Protbuf's "ZigZag" encoding.

### Struct

Similar to Protobuf's messages, their fields are numbered from 0.  Structs are groups of values, each structured as a field identification byte followed by as many values as the byte specifies.  Fields must thus be encoded in ascending numeric order.  The initial implied previous field ID is -1, so the Delta of an initial field 0 is 0.

| Byte (`c`) | Condition | Description                                                 |
| ---------- | --------- | ----------------------------------------------------------- |
| `0_______` | `< 128`   | Delta (1..128) from previous field ID, 1 value follows      |
| `10000000` | `== 128`  | Close nearest `Struct Open`                                 |
| `1_______` |           | `c - 128` maps the next 7 fields, 1 value per 1 bit follows |

Field numbers and names should remain reserved forever when they are deprecated to avoid version conflicts.

## DATA TYPES

These higher-level types are standard (to be preferred to alternatives) but optional (implemented as needed).  They are not distinguished explicitly on the wire: applications agree out-of-band about when to use what, much like Protobuf, Thrift, etc.

| Name                   | Wire Encoding                                                                 |
| ---------------------- | ----------------------------------------------------------------------------- |
| `undefined`            | In a `struct`, the absence of a field                                         |
| `null`                 | Null                                                                          |
| `list`/`…s`            | List(0..3) + 0..3 vals / List Open + vals + Close                             |
| `map`                  | `list` of alternating keys and values, in ascending key order for determinism |
| `string`/`str`         | Data(0,2,4,8) + 0,2,4,8 bytes / Data + V + N bytes as UTF-8                   |
| `bytes`/`data`         | Same as `string` but without implied UTF-8                                    |
| `bool`                 | Int values `0` and `1`                                                        |
| `uint`                 | Int                                                                           |
| `int`                  | Int signed ("ZigZag")                                                         |
| `enum`                 | `uint`                                                                        |
| `variant`              | `list[uint,args…]` / `uint`                                                   |
| `id`/`guid`/`uuid`     | `uint` or `string` depending on source type                                   |
| `code`                 | `uint` interpreted as base-36 up to 12 chars (i.e. "USD" is `0x9BDD`)         |
| `binary`/`float`/`fp`  | `bytes` as IEEE 754 float binary 16,32,64,128,256 precisions                  |
| `decimal`/`dec`        | `uint` as signed digits `<< 4` and 0..15 decimal places                       |
| `ratio`                | `list[int,uint]`                                                              |
| `percent`/`pct`        | `decimal` rebased to 1 (i.e. 50% is 0.5)                                      |
| `struct`/`obj`         | Struct(0..3) + groups / Struct + groups + Close / `uint` (see References)     |
| `mask`                 | `list` of a mix of `uint` and `list` (recursive)                              |
| `datetime`/`date`/`dt` | Struct of up to 7 fields (see Datetime)                                       |
| `timestamp`/`ts`       | `int` seconds since UNIX Epoch `- 1_677_283_227`                              |
| `language`/`lang`      | `code` IETF BCP-47                                                            |
| `country`/`cntry`      | `code` ISO 3166-1 alpha-2                                                     |
| `region`/`rgn`         | `code` ISO 3166-2 alpha-1/3 (no country prefix)                               |
| `currency`/`curr`      | `code` ISO 4217 alpha-3                                                       |
| `unit`                 | `code` UN/CEFACT Recommendation 20 unit of measure                            |
| `text`                 | `map` of `lang,string` pairs / `string`                                       |
| `amount`/`amt`         | `list[decimal,currency]` / `decimal`                                          |
| `quantity`/`qty`       | `list[decimal,unit]` / `decimal`                                              |
| `ip`                   | `bytes` with 4 or 16 bytes (IPv4 or IPv6)                                     |
| `subnet`/`cidr`/`net`  | `list[ip,uint]` CIDR notation: IP with netmask size in bits                   |

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

To keep implementations light and efficient, `struct` reference support is limited to the specific but highly useful scenario of fields named `guid` or `uuid`. Those keys are considered globally unique, so when encoders encounter the same IDs again they may replace duplicates with their unwrapped `guid` or `uuid` value (in that order of preference) which is `uint` or `string`.  This is unambiguous since a `struct` is expected by decoders.

For applications with table-specific ID namespaces, one strategy to benefit from references could be to fake GUIDs on the wire by prefixing a namespace to the ID in a `string`. For example, a single character followed by a Base-32 Crockford encoding of the ID could be readable yet short, such that "color 1234" might be "C16J", or "size 515" could be "SG3".  An equivalent `uint` strategy could be to left-shift the sequence by a fixed global number of bits (i.e. if the company has 11 types, maybe shift left by 4, allowing up to 16 types forever)
