# Vanilla Object Format

VOF specifies high-level data types and API design concepts, which can be encoded as:

* **JSON:** Human-readable formats, easy to use by third parties
* **CBOR:** Compact data representations, while relying on proven encoders
* **VOF Binary:** Most compact data representation, efficient encoding, but "yet another serialization format"

Encoders are encouraged to use Gzip or Zstd compression for VOF messages exceeding 100-200 bytes.  Decoders can always know unambiguously the format of VOF data by inspecting the first few bytes:

| First byte(s)       | Unique meaning                  |
|---------------------|---------------------------------|
| 0x1F 0x8B           | Gzip                            |
| 0x28 0xB5 0x2F 0xFD | Zstd                            |
| 0x5B or 0x7B        | JSON (array, object)            |
| 0x80-0xDF           | CBOR (array, map, tag, magic)   |
| 0xEB-0xFF           | VOF Binary (non-numeric, magic) |

## Data Types

These are standard (to be preferred to alternatives) but optional (implemented as needed).  They are not distinguished explicitly on the wire: applications agree out-of-band about when to use what, much like Protobuf, Thrift, etc.  As such, types such as decimal and coordinates do not use explicit tags in the CBOR encoding, favoring compactness.  See `BINARY.md` for details of VOF's own binary encoding and advanced semantic tag use.

| Type Name         | VOF Binary                                               | CBOR            | JSON                                                         |
| ----------------- | -------------------------------------------------------- | --------------- | ------------------------------------------------------------ |
| `null`            | Null                                                     | _same_          | _same_                                                       |
| `bool`            | False: Int 0 / True: Int 1                               | False, True     | Boolean                                                      |
| `list`            | List(0..8) + 0..8 vals<br />List Open + vals + Close     | Array           | Array                                                        |
| `ndarray`         | `list[[sizes…], values…]`                                | _same_          | Array (nested)                                               |
| `map`             | `list` alternating keys and values                       | Map             | Object                                                       |
| `variant`/`enum`  | `list[Int,values…]` / `Int`                              | _same_          | Array[String,values…] / String                               |
| `struct`          | S.Open + groups…                                         | Map (keys: IDs) | Object (keys: names)                                         |
| `series`          | `list[[IDs…], values…]`                                  | _same_          | 2D Array (row 0: names)                                      |
| `string`          | String + size + bytes as UTF-8                           | String          | String (necessarily UTF-8)                                   |
| `bytes`/`data`    | Data + size + raw bytes                                  | String          | String base-64 URL encoded                                   |
| `uint`            | Int                                                      | Int             | Number / `decimal`                                           |
| `int`/`sint`      | Int signed                                               | Int             | Number / `decimal`                                           |
| `decimal`/`dec`   | `sint << 3` + 0..9 places                                | _same_          | String: optional `-` + 1+ digits + possibly `.` and 1+ digits |
| `ratio`           | `list[int,uint]`                                         | _same_          | String: optional `-` + digits + `/` + digits                 |
| `percent`         | `dec` rebased to 1 (i.e. 50% is 0.5)                     | _same_          | String: `decimal` hundredths + `%`                           |
| `float32`         | Float 32                                                 | Float           | Number                                                       |
| `float64`         | Float 64                                                 | Float           | Number                                                       |
| `date`/`_on`      | `uint`                                                   | _same_          | `uint` as `YYYYMMDD`                                         |
| `datetime`/`time` | `uint`                                                   | _same_          | `uint` as `YYYYMMDDHHMM`                                     |
| `timestamp`       | `int` Epoch `- 1,750,750,750`                            | _same_          | _same_                                                       |
| `timespan`/`span` | `list[int,int,int]`                                      | _same_          | _same_                                                       |
| `code`            | `string` strictly `[A-Z0-9_]`                            | _same_          | _same_                                                       |
| `language`/`lang` | `code` IETF BCP-47                                       | _same_          | _same_                                                       |
| `country`/`cntry` | `code` ISO 3166-1 alpha-2                                | _same_          | _same_                                                       |
| `region`/`rgn`    | `code` ISO 3166-2 alpha-1/3<br />(no country prefix)     | _same_          | _same_                                                       |
| `currency`/`curr` | `code` ISO 4217 alpha-3                                  | _same_          | _same_                                                       |
| `tax_code`        | `code` "CC[_RRR]_X"<br />ISO 3166-1, ISO 3166-2, acronym | _same_          | _same_                                                       |
| `unit`            | `code` UN/CEFACT Rec. 20                                 | _same_          | _same_                                                       |
| `text`            | `map` of `lang,string` pairs<br />`string` for just one  | _same_          | _same_                                                       |
| `amount`/`price`  | `list[dec,curr]` / `dec`                                 | _same_          | String: `dec`<br />+ optional space and `curr`               |
| `tax`/`tax_amt`   | `list[dec,tax_code,curr]`<br />`list[dec,tax_code]`      | _same_          | String: `dec`<br />+ optional space and `curr`<br />+ mandatory space + `tax_code` |
| `quantity`        | `list[dec,unit]` / `dec`                                 | _same_          | String: `dec`<br />+ optional space and `unit`               |
| `ip`              | `bytes` with 4 or 16 bytes                               | _same_          | String: IPv4 or IPv6 notation                                |
| `subnet`/`net`    | `list[ip,uint]` CIDR notation                            | _same_          | String: CIDR notation                                        |
| `coords`          | `list[dec,dec]` WGS84                                    | _same_          | _same_                                                       |

### Variant / Enum / Struct

Identifiers are unsigned integers starting from 0 (CBOR/Binary, similar to Protobuf) and strings (JSON).  To avoid version conflicts, **identifiers must remain reserved forever when they are deprecated.**  Variants and Enums should have their first or all letters uppercase while Struct field names should begin with a lowercase letter.

In CBOR/Binary, variants, enums and struct fields are identified by a unique unsigned integer (similar to Protobuf), which should also be reserved forever.  For a given context (for example, a company's HTTP API), encoders should maintain a global, namespaced symbol table.  Applications calling encoder functions for these three types must provide a namespace (i.e. `com.example.order.line`) in which field names will be assigned integers starting from zero as they are first encountered.  This table must be managed centrally and shared with other endpoints (much like Protobuf IDL `.proto` files must be shared among endpoints).

Symbol tables are simple JSON files, an object with nested namespace components.  Each final object must be sorted by integer ID to facilitate version control and manual editing.  Implementations using a read-only symbol table (normal production use) should fail when encountering an unknown namespace, name or ID.

```json
{
  "com.example.order.line": {
    "i": 0,
    "product": 1,
    "qty": 2,
    "unit_price": 3
  }
}
```

### NDArray

Fixed-size multi-dimensional lists.  This is a list where the first item is a list of dimension sizes, followed by each value from zero-index onward, exactly as many values as the product of all dimension sizes.

For example, a 3D array of size 2x2x2 could be: `[[2,2,2],1,2,3,4,5,6,7,8]`

### Series

Compact representation of a list of `struct` where all the same fields are defined (typical of time series data, product price lists, etc.)  In JSON, this is a 2-D Array where the first row selects fields by name and each subsequent row is an Array with just those values.  In CBOR/Binary, this is a flat list where the first item is a list of numeric field IDs and the other items are the values of each struct, one after the other (no wrapping necessary).

### Decimal

Necessary for financial data.  In CBOR/Binary, this is passed to the encoder as a signed integer left-shifted 3 bits to add a 3-bit value representing 0, 1, 2, 3, 4, 5, 6 or 9 decimal places.  For example, -2.135 would be `(-2135 << 3) + 3 = -17083`.  In JSON, it must be a String to bypass possible float conversions done by some libraries.

### Date

Calendar date, sortable.  Time zone is outside the scope of this type, derived from context as necessary.  In JSON, a human-friendly `YYYYMMDD` number is used.  In CBOR/Binary, it is structured in 17 bits as `(year << 9) + (month << 5) + day` where:

* **year** — Number of years since 1900 (i.e. 2025 is 125)
* **month** — 1..12
* **day** — 1..31

### Datetime

Extends `date` with wall clock time, still sortable and with implicit time zone.  In JSON, a human-friendly `YYYYMMDDHHMM` number is used.  In CBOR/Binary, it is structured with minute precision in 28 bits as `(year << 20) + (month << 16) + (day << 11) + (hour << 6) + minute` where:

* **year** — Number of years since 1900 (i.e. 2025 is 125)
* **month** — 1..12
* **day** — 1..31
* **hour** — 0..23
* **minute** — 0..59

### Timespan

Calendar duration expressed as half-months, days and seconds, each signed and applied in three steps in that order when it is used.  For example, "one year minus one day" would be `[24,-1,0]`.

### Text

If multiple strings are provided with the same language code, the first one wins.  Used in its bare `string` form, it is up to the applications to agree on the choice of default language.

The canonical encoding is to use the bare `string` form when a single language is used and corresponds to the default language (if one is defined), to minimize space.

## JSON Encoding

* The regular MIME type (`application/json`) for JSON encoded transfers is recommended for compatibility.

* When possible, Objects should be sorted by ascending key when buffering the whole list is possible, to facilitate compression.

* Number, `decimal` and `ratio` must strip leading zeros and trailing decimal zeros.

* Integers must only encode as `decimal` when they are outside of JavaScript `MIN/MAX_SAFE_INTEGER` range.

## CBOR Encoding

* The regular MIME type (`application/cbor`) for CBOR encoded transfers is recommended.
* When possible, Maps should be sorted by ascending key when buffering the whole list is possible, to facilitate compression.  This is usually done by using a CBOR encoder in deterministic "canonical" mode, but some implementations may require applications to pass sorted lists to encoders to achieve this manually.
* You may begin a stream with CBOR's magic, tag 55799.  No other tags should be used.

## Binary Encoding

* The suggested MIME type for binary encoded transfers is `application/x-vanilla-object`.  The suggested file name extension is `.vo`.
* When possible, Maps should be sorted by ascending key when buffering the whole list is possible, to facilitate compression.
* You may begin a stream with VOF Binary's magic, tag 5505 applied to integer 79, which encodes to `0xFF81564F`.

## API Best Practices

**TODO:** designing collections (heaps and refs, which the IDL allows creating just fine like our former Protobuf Request/Response messages), using `select~` query parameters instead of Protobuf's FieldMask, making filtering query parameters

## Implementation Considerations

### Series

Encoders should use the first object of the list to determine the structure of all objects in the list.  They should fail if a subsequent member has extra fields set.  If subsequent members are missing any fields though, encoders should encode `Null` for them in order to keep going.

## Design Compromises

* The `decimal`, `date` and `datetime` types were designed for financial systems based on SQLite and kept here for their compact sizes.
* The `code` type was initially designed as a base 37 `uint`, but the space savings were not worth the implementation complexity.
* The last size of `decimal` is 9 and not 7 in order to match the maximum precision allowed in some other business contexts such as ANSI X12.
