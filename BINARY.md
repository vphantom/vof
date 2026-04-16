# VOF Binary Encoding

A VOF Binary chunk is a stream of control values, each sometimes followed by data as specified by the value itself.

Decoders encountering impossible input (including invalid UTF-8 in `string` data) should discard the entire chunk and return an appropriate error.

## Control Values

Small integers are compressed at the slight expense of larger ones similarly to the Prefix Varint format (itself a variation on LEB128 and VLQ but eliminating loops, most shifts and representing 64 bits in 9 bytes instead of 10).  Extra bytes for the multi-byte integers are in Little Endian order, so any bits in the initial byte are the least significant.  Illustrated here from the decoder point of view, we see that very little computing is involved:

| Byte (`c`) | Type               | Condition | Description / Operation                         |
| ---------- | ------------------ | --------- | ----------------------------------------------- |
| `0_______` | Int 7-bit          | `< 128`   | `c`                                             |
| `10______` | Int 14-bit         | `< 192`   | `(next_byte() << 6) + c - 128`                  |
| `1100____` | Int 20-bit         | `< 208`   | `(next_bytes_le(2) << 4) + c - 192`             |
| `11010___` | Int 27-bit         | `< 216`   | `(next_bytes_le(3) << 3) + c - 208`             |
|            | Int 32,40,48,56,64 | `< 221`   | Next 4,5,6,7,8 bytes are int Little Endian      |
|            | Float 16,32,64     | `< 224`   | Next 2,4,8 bytes are IEEE 754 Little Endian     |
|            | String (0..7)      | `< 232`   | Exactly `c - 224` UTF-8 bytes                   |
|            | List (0..11)       | `< 244`   | Exactly `c - 232` values (no Close)             |
|            | Gap (1..4)         | `< 248`   | Represents `c - 243` undefined values           |
|            | String             | `== 248`  | Next is size in bytes, then as many UTF-8 bytes |
|            | Data               | `== 249`  | Next is size in bytes, then as many raw bytes   |
|            | List Open          | `== 250`  | Values until `List Close`                       |
|            | List Close         | `== 251`  | Close nearest `List Open`                       |
|            | Gap                | `== 252`  | Next Int is number of undefined values          |
|            | Alt                | `== 253`  | Next value is in its alternate form, `Tag(-1)`  |
|            | Tag                | `== 254`  | Next Int qualifies next value                   |
|            | Null               |           |                                                 |

### Canonical Encoding

* Integers, floating point numbers and decimals numbers must be encoded in the smallest form which does not lose precision.  Note that floats `-0.0` and `+0.0` are _not_ considered equivalent, however all `NaN` bit patterns are considered equal (just pick one for consistency within the current output).  When converting between float precisions, denormalized numbers should be normalized if the target precision can represent the exact value as a normal number.
* Strings of 0..7 characters must be encoded with the short forms 224..231.
* Lists of 0..11 items must be encoded with the short forms 232..243.
* Gaps of less than 5 undefined values must be encoded with short forms 244..247.
* Maps are lists of alternating keys and values.
* Boolean values are integers 0 for False and 1 for True.

### Negative Integers

When considered signed, integers' least significant bit before encoding into the above indicates the sign.  Encoding from typical 2's complement is `(i >> (int_size - 1)) XOR (i << 1)` and decoding is `(value >> 1) XOR -(value AND 1)`.  This is identical to Protbuf's "ZigZag" encoding.

## Implementation Considerations

### Decoding Security

Implementations should consider reasonable limits on:

* Total nesting depth (128 might be reasonable)
* Maximum string length (1MB to 1GB might be reasonable)
* Maximum number of object members (1K might be reasonable)
* Maximum number of list elements (1M might be reasonable)
* Time to wait between values and/or overall rate limiting

Decoded data (and thus string) sizes must be checked for overflow: a corrupt or malicious size could extend well beyond the input.
