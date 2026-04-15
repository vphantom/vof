# VOF Binary Encoding

A VOF Binary chunk is a stream of control values, each sometimes followed by data as specified by the value itself.

Decoders encountering impossible input (including invalid UTF-8 in `string` data) should discard the entire chunk and return an appropriate error.

## Control Values

Small integers are compressed at the slight expense of larger ones similarly to the Prefix Varint format (itself a variation on LEB128 and VLQ but eliminating loops, most shifts and representing 64 bits in 9 bytes instead of 10).  Extra bytes for the multi-byte integers are in Little Endian order, so any bits in the initial byte are the least significant.  Illustrated here from the decoder point of view, we see that very little computing is involved:

| Byte (`c`) | Type               | Condition | Description / Operation                         |
| ---------- | ------------------ | --------- | ----------------------------------------------- |
| `0_______` | Int 7-bit          | `< 128`   | `c`                                             |
| `10______` | Int 14-bit         | `< 192`   | `(next_byte() << 6) + c - 128`                  |
| `110_____` | Int 21-bit         | `< 224`   | `(next_bytes_le(2) << 5) + c - 192`             |
| `1110000_` | Int 25-bit         | `< 226`   | `(next_bytes_le(3) << 1) + c - 224`             |
|            | Int 32,40,48,56,64 | `< 231`   | Next 4,5,6,7,8 bytes are int Little Endian      |
|            | Float 16,32,64     | `< 234`   | Next 2,4,8 bytes are IEEE 754 Little Endian     |
|            | List (0..7)        | `< 242`   | Exactly `c - 234` values (no Close)             |
|            | List Open          | `== 242`  | Values until `List Close`                       |
|            | List Close         | `== 243`  | Close nearest `List Open`                       |
|            | Undefined          | `== 244`  |                                                 |
|            | Gap (2..7)         | `< 251`   | Multiple (`c - 243`) undefined values           |
|            | Gap                | `== 251`  | Next is number of undefined values              |
|            | String             | `== 252`  | Next is size in bytes, then as many UTF-8 bytes |
|            | Data               | `== 253`  | Next is size in bytes, then as many raw bytes   |
|            | Alt                | `== 254`  | Next value is in its alternate form             |
|            | Null               |           |                                                 |

### Canonical Encoding

* Integers and `decimal` must be encoded in the smallest form possible.  For example, 1.1 should only be "11 with 1 decimal place."
* Floating point numbers must be represented in the smallest form which does not lose precision.  Note that `-0.0` and `+0.0` are _not_ considered equivalent, however all `NaN` bit patterns are considered equal.  When converting between precisions, denormalized numbers should be normalized if the target precision can represent the exact value as a normal number.  This ensures minimal representation while maintaining precision.
* Lists of 0..7 items must be encoded with the short forms 234..241.
* Gaps of less than 8 undefined values must be encoded with short forms 244..250.
* Maps are lists of alternating keys and values.
* Boolean values are integers 0 for False and 1 for True.

### Negative Integers

When an integer is considered signed, its least significant bit before encoding into the above indicates the sign.  Encoding from typical 2's complement is `(i >> (int_size - 1)) XOR (i << 1)` and decoding is `(value >> 1) XOR -(value AND 1)`.  This is identical to Protbuf's "ZigZag" encoding.

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
