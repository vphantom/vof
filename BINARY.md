# VOF Binary Encoding

A VOF Binary chunk is a stream of control values, each sometimes followed by data as specified by the value itself.

Decoders encountering impossible input (including invalid UTF-8 in `string` data) should discard the entire chunk and return an appropriate error.

## Control Values

Small integers are compressed at the slight expense of larger ones similarly to the Prefix Varint format (itself a variation on LEB128 and VLQ which eliminates loops, most shifts and represents 64 bits in 9 bytes instead of 10).  Extra bytes for the multi-byte integers are in Little Endian order, so any bits in the initial byte are the least significant.  Illustrated here from the decoder point of view, we see that very little computing is involved:

| Byte (`c`) | Type               | Condition | Description / Operation                           |
| ---------- | ------------------ | --------- | ------------------------------------------------- |
| `0_______` | Int 7-bit          | `< 128`   | `c`                                               |
| `10______` | Int 14-bit         | `< 192`   | `(next_byte() << 6) + c - 128`                    |
| `110_____` | Int 21-bit         | `< 224`   | `(next_bytes_le(2) << 5) + c - 192`               |
| `111000__` | Int 26-bit         | `< 228`   | `(next_bytes_le(3) << 2) + c - 224`               |
|            | Int 32,40,48,56,64 | `< 233`   | Next 4,5,6,7,8 bytes are int Little Endian        |
|            | Float 32,64        | `< 235`   | Next 4,8 bytes are IEEE 754 Little Endian         |
|            | Null               | `== 235`  |                                                   |
|            | String             | `== 236`  | Next is size in bytes, then as many UTF-8 bytes   |
|            | Struct Open        | `== 237`  | Open (groups until Struct Close)                  |
|            | List Open          | `== 238`  | Values until `List Close`                         |
|            | Close              | `== 239`  | Close nearest `List Open` or `Series`             |
|            | List               | `< 249`   | Exactly 0..8 items (no Close)                     |
|            | Series             | `== 249`  | Next: headcount, heads..., values...              |
|            | Data               | `== 250`  | Next is size in bytes, then as many raw bytes     |
|            | _reserved_         | `< 255`   | Next is size in bytes, then as many raw bytes     |
|            | Tag                |           | Next value is Int qualifier, then qualified value |

### Canonical Encoding

* Integers and `decimal` must be encoded in the smallest form possible.  For example, 1.1 should only be "11 with 1 decimal place."

* Floating point numbers must be represented in the smallest form which does not lose precision.  Note that `-0.0` and `+0.0` are _not_ considered equivalent, however all `NaN` bit patterns are considered equal.  When converting between precisions, denormalized numbers should be normalized if the target precision can represent the exact value as a normal number.  This ensures minimal representation while maintaining precision.

* Lists used as maps (odd keys, even values) should be sorted by ascending key when buffering the whole list is possible, to facilitate compression.

* Lists of 0..8 items must be encoded with the short forms 240..248.  Thus maps of 0..4 pairs must be encoded as 242, 244, 246, 248.

* Tags should not be used unless strictly necessary.

### Negative Integers

When an integer is considered signed, its least significant bit before encoding into the above indicates the sign.  Encoding from typical 2's complement is `(i >> (int_size - 1)) XOR (i << 1)` and decoding is `(value >> 1) XOR -(value AND 1)`.  This is identical to Protbuf's "ZigZag" encoding.

### Struct

Similar to Protobuf's messages, although our fields are numbered from 0.  Structs are groups of values, each structured as a field identification byte followed by as many values as the header byte specifies.  Fields must thus be encoded in ascending numeric order.

Within a struct (after a `Struct Open` control value), fields are organized into groups for efficiency. Each group begins with a header byte that indicates which fields are present:

* Gap: under 128 is the number of fields to skip after the last field ID, which will be followed by a single value.
* Struct Close: value 128 closes the nearest `Struct Open`.
* Field Map: over 128, the least significant 7 bits form a bitmap indicating which of the next 7 next field IDs (relative to the last) are present, followed by as many values as the bitmap has 1 bits set.

Example header bytes:
* `00000010` (2) means skip 2 field IDs (i.e. if the last field ID was 3, we now encode ID 6)
* `11100000` (224) means fields at positions +0, +1 are present, but +2 through +6 are absent
* `10000001` (129) means fields at positions +0, +6 are present, but +1 through +5 are absent

### Series

Following the control value is an `Int` specifying how many struct header bytes there are, followed by as many header bytes as specified.  Each value of each `Struct` is then added, so this implies the same value count for each instance.  The series is concluded with `Close`.

For example, a list of 3 objects each with fields 0,1,2 could be: 249, 1, 135, 1, 1, 1, 2, 2, 2, 3, 3, 3, 239

### Tagged Values

Tags 0..63 are available for applications to define their own types from our basic types and 64+ are reserved.  For example, a user-defined "URL" type could be decided as Tag 0 followed by a `string`.  Obviously, this means that such tags may have completely different meanings across different applications, so their use makes the resulting data non-portable.  Decoders should fail when presented with unknown tags.

In JSON intended to be compatible with VOF Binary, tags are represented as objects with a single member whose key is a string starting with "@" followed by a number 0..63, with the value being the tagged value. For example, a user-defined "URL" type could be designed as `{"@0": "https://example.com"}`.

In CBOR intended to be compatible with VOF Binary, tag use may conflict with CBOR's own tag number allocations.

Future versions of VOF may reserve tags 64+ for our defined data types (i.e. `bool`, `string`, `datetime`) for situations where additional type clarity is required in encoded data.

## Implementation Considerations

### Reserved Types

The 4 reserved control values are predetermined to use the same structure as `Data`: an unsigned number of bytes follows, and then as many bytes as specified.  This makes room for future types such as large integers or floats while guaranteeing that older decoders can safely skip over such unknown value types.

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

## Design Compromises

* Types: `float16` was omitted because it was deemed too rare.
* ZigZag negative integer encoding was chosen because it is both simpler to implement and slightly more compact than dedicating a distinct bit for the sign, which would allow for a redundant `-0` value.
* The `collection` type was favored vs low-level byte offset references for simplicity.
