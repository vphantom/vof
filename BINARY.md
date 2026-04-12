# VOF Binary Encoding

A VOF Binary chunk is a stream of control values, each sometimes followed by data as specified by the value itself.

Decoders encountering impossible input (including invalid UTF-8 in `string` data) should discard the entire chunk and return an appropriate error.

**WARNING:** This specification is currently under review.  The Record type may be removed before this format is finalized.

## Control Values

Small integers are compressed at the slight expense of larger ones similarly to the Prefix Varint format (itself a variation on LEB128 and VLQ but eliminating loops, most shifts and representing 64 bits in 9 bytes instead of 10).  Extra bytes for the multi-byte integers are in Little Endian order, so any bits in the initial byte are the least significant.  Illustrated here from the decoder point of view, we see that very little computing is involved:

| Byte (`c`) | Type               | Condition | Description / Operation                         |
| ---------- | ------------------ | --------- | ----------------------------------------------- |
| `0_______` | Int 7-bit          | `< 128`   | `c`                                             |
| `10______` | Int 14-bit         | `< 192`   | `(next_byte() << 6) + c - 128`                  |
| `110_____` | Int 21-bit         | `< 224`   | `(next_bytes_le(2) << 5) + c - 192`             |
| `11100___` | Int 27-bit         | `< 232`   | `(next_bytes_le(3) << 2) + c - 224`             |
|            | Int 32,40,48,56,64 | `< 237`   | Next 4,5,6,7,8 bytes are int Little Endian      |
|            | Float 16,32,64     | `< 240`   | Next 2,4,8 bytes are IEEE 754 Little Endian     |
|            | List               | `< 249`   | Exactly `c - 240` values (no Close)             |
|            | List Open          | `== 249`  | Values until `List Close`                       |
|            | Close              | `== 250`  | Close nearest `List Open`                       |
|            | Record Open        | `== 251`  | Open (groups until Record Close)                |
|            | String             | `== 252`  | Next is size in bytes, then as many UTF-8 bytes |
|            | Data               | `== 253`  | Next is size in bytes, then as many raw bytes   |
|            | Alt                | `== 254`  | Next value is in its alternate form             |
|            | Null               |           |                                                 |

### Canonical Encoding

* Integers and `decimal` must be encoded in the smallest form possible.  For example, 1.1 should only be "11 with 1 decimal place."
* Floating point numbers must be represented in the smallest form which does not lose precision.  Note that `-0.0` and `+0.0` are _not_ considered equivalent, however all `NaN` bit patterns are considered equal.  When converting between precisions, denormalized numbers should be normalized if the target precision can represent the exact value as a normal number.  This ensures minimal representation while maintaining precision.
* Lists of 0..8 items must be encoded with the short forms 240..248.
* Maps are lists of alternating keys and values.
* Boolean values are integers 0 for False and 1 for True.

### Negative Integers

When an integer is considered signed, its least significant bit before encoding into the above indicates the sign.  Encoding from typical 2's complement is `(i >> (int_size - 1)) XOR (i << 1)` and decoding is `(value >> 1) XOR -(value AND 1)`.  This is identical to Protbuf's "ZigZag" encoding.

### Record

Records are groups of values, each structured as a field selector byte followed by as many values as that byte specifies.  Fields must thus not be duplicated and be encoded in ascending numeric order.  A regular list of alternating field IDs and values should be used for sparse cases where there are gaps of 64+ between fields to be encoded.  Field selector bytes are structured as:

* **Most Significant Bit:** continuation indicator
  * `0` — this is the last group
  * `1` — more groups will follow after this group's values
* **Next Bit:**
  * `0` — Gap: the last 6 bits represent 0..63 fields to skip after the last field ID; a single value follows this
  * `1` — Map: the last 6 bits represent the presence of the next 6 field IDs (relative to the last); as many values follow as the bitmap has 1 bits set.

Example selector bytes:

* `00000010` — last group, skip 2 field IDs (i.e. if the last field was 3, the next value is for ID 6)

* `11110000` — more groups follow, fields +0, +1 follow, +2, +3, +4, +5 are omitted
* `01100001` — last group, fields +0 and +5 follow, while +1, +2, +3, +4 are omitted

## Implementation Considerations

### Maps

Decoders should use the last value when a key is present multiple times.

### Decoding Security

Implementations should consider reasonable limits on:

* Total nesting depth (128 might be reasonable)
* Maximum string length (1MB to 1GB might be reasonable)
* Maximum number of object members (1K might be reasonable)
* Maximum number of list elements (1M might be reasonable)
* Time to wait between values and/or overall rate limiting

Decoded data (and thus string) sizes must be checked for overflow: a corrupt or malicious size could extend well beyond the input.
