# Vanilla Object Format — Binary

## WIRE FORMAT

A Vanilla Object Format chunk is a stream of control values, each sometimes followed by data as specified by the value itself.

Optionally, writers may prefix their output with `0x566F461A` ("VoF^Z") as a format magic number.

The suggested MIME type for binary encoded transfers is `application/x-vanilla-object` while JSON remains `application/json`.

The suggested file name extension is `.vof`.

### Control Values

Similar to the Prefix Varint encoding (itself an order of magnitude simpler than LEB128 at run-time), we prioritize the compactness of small integers at the slight expense of larger ones.  Extra bytes for the `Int` types are in Little Endian order, thus any bits from the initial byte are the least significant.  Illustrated from the decoding point of view:

| Character  | Bytes   | Type        | Condition | Operation                                                         |
| ---------- | ------- | ----------- | --------- | ----------------------------------------------------------------- |
| `0_______` | 1       | Int 7-bit   | `< 128`   | `c`                                                               |
| `10______` | 2       | Int 14-bit  | `< 192`   | `(next_bytes_le(1) << 6) + c - 128`                               |
| `110_____` | 3       | Int 21-bit  | `< 224`   | `(next_bytes_le(2) << 5) + c - 192`                               |
| `11100___` | 4       | Int 27-bit  | `< 232`   | `(next_bytes_le(3) << 4) + c - 224`                               |
| `111010__` | 1       | List        | `< 236`   | Exactly `c - 232` items (0..3)                                    |
| `111011__` | 1       | Struct      | `< 240`   | Exactly `c - 236` groups (0..3)                                   |
| `1111000_` | 5       | Int 33-bit  | `< 242`   | `(next_bytes_le(4) << 1) + c - 240`                               |
|            | 1       | Close       | `== 242`  | Close nearest `List` or `Struct`                                  |
|            | 1       | List Open   | `== 243`  | Items until `Close`                                               |
|            | 1       | Struct Open | `== 244`  | Groups until `Close`                                              |
|            | 1+V+N   | Data        | `== 245`  | Next `Int` V is size N in bytes                                   |
|            | 1       | Data        | `== 246`  | Data (empty)                                                      |
|            | 3       | Data        | `== 247`  | Data (2 bytes)                                                    |
|            | 5       | Data        | `== 248`  | Data (4 bytes)                                                    |
|            | 9       | Data        | `== 249`  | Data (8 bytes)                                                    |
|            | 1       | Null        | `== 250`  |                                                                   |
|            | 6       | Int 40-bit  | `== 251`  | `next_bytes_le(5)`                                                |
|            | 7       | Int 48-bit  | `== 252`  | `next_bytes_le(6)`                                                |
|            | 8       | Int 56-bit  | `== 253`  | `next_bytes_le(7)`                                                |
|            | 9       | Int 64-bit  | `== 254`  | `next_bytes_le(8)`                                                |
|            | 1+V1+V2 | Tag         |           | Next V1 is tag qualifying V2<br/>0..63 user-defined, 64+ reserved |

Lists of 0, 1, 2, 3 items, structs of 0, 1, 2, 3 groups and Data with 0, 2, 4, 8 bytes should be encoded in their short form.  Integers should be encoded in the smallest form possible.

### Implicit List

A chunk is considered an implicit list without the initial `List Open` nor the final `Close` bytes.  Therefore, a 7-bit ASCII file may be decoded as a valid list of 7-bit integers.

### Int Optionally Signed

When an integer is considered signed, its least significant bit before encoding into the above indicates the sign.  Encoding from typical 2's complement is `(i >> (int_size - 1)) XOR (i << 1)` and decoding is `(value >> 1) XOR -(value AND 1)`.  This is identical to Protbuf's "ZigZag" encoding.

### Struct

Similar to Protobuf's messages, their fields are numbered from 0.  Structs are groups of values, each structured as a field identification byte followed by as many values as the byte specifies.  Fields must thus be encoded in ascending numeric order.

| Byte       | Description                                           |
| ---------- | ----------------------------------------------------- |
| `0_______` | Delta (1..128) from previous field ID, `count = 1`    |
| `1_______` | Map of the next 7 fields, `count` is number of 1 bits |

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
| `decimal`/`dec`        | `uint` (signed digits `<< 4`) + 0..15 decimal places                          |
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
