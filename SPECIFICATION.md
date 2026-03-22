# Vanilla Object Format

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
| `record`          | S.Open + groups…                                         | Map (keys: IDs) | Object (keys: names)                                         |
| `series`          | `list[[IDs…], values…]`                                  | _same_          | 2D Array (row 0: names)                                      |
| `string`          | String + size + bytes as UTF-8                           | String          | String (necessarily UTF-8)                                   |
| `bytes`/`data`    | Data + size + raw bytes                                  | String          | String base-64 URL encoded                                   |
| `uint`            | Int                                                      | Int             | Number / String if outside MIN/MAX for float64               |
| `int`/`sint`      | Int signed                                               | Int             | Number / String if outside MIN/MAX for float64               |
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

### Units of measure

We use codes from UN/CEFACT Recommendation 20.  See full list at: [unece.org](https://tfig.unece.org/contents/recommendation-20.htm).  Quantities should default to `EA` (each) when they do not carry an explicit unit code.  Here are some of the most common codes:

| Category | Units                                                        |
| -------- | ------------------------------------------------------------ |
| Grouping | `EA` Each • `PR` Pair • `P3` Three-pack • `P4` Four-pack • `P5` Five-pack • `P6` Six-pack • `P8` Eight-pack • `DZN` Dozen • `CEN` Hundred |
| Form     | `AY` Assembly • `CG` Card • `DC` Disk • `NF` Message • `NV` Vehicle • `RU` Run • `SET` Set • `SX` Shipment • `ZP` Page |
| Time     | `SEC` Second • `MIN` Minute • `HUR` Hour • `LH` Labor hour • `DAY` Day • `MON` Month • `ANN` Year |
| Weight   | `GRM` Gram • `KGM` Kilogram • `LBR` Pound                    |
| Length   | `CMT` Centimetre • `MTR` Metre • `INH` Inch • `FOT` Foot • `YRD` Yard |
| Area     | `CMK` Square centimetre • `MTK` Square meter • `INK` Square inch • `FTK` Square foot • `YDK` Square yard |
| Volume   | `MLT` Millilitre • `LTR` Litre • `INQ` Cubic inch • `ONZ` Ounce • `OZA` Fluid ounce US • `OZI` Fluid ounce UK • `QT` Quart US • `QTI` Quart UK • `GLL` Gallon US • `GLI` Gallon UK |
| Energy   | `KWH` Kilowatt hour                                          |
| Data     | `2P` Kilobyte • `4L` Megabyte            |

### Namespaces: Variant, Enum, Record

A project or API has a root namespace, i.e. `com/example`.

Variant, Enum and Record types need unique namespaces in plural form for API consistency purposes, for example: `com/example/orders/lines`

Identifiers within a namespace are strings (JSON) and unsigned integers starting from 0 (CBOR/Binary, similar to Protobuf).  To avoid version conflicts, **identifiers must remain reserved forever when they are deprecated.**  Variants and Enums should have their first or all letters uppercase while record field names should begin with a lowercase letter.

In CBOR/Binary, variants, enums and record fields are identified by a unique unsigned integer (similar to Protobuf), which should also be reserved forever.  For a given context (for example, a company's HTTP API), encoders should maintain a global, namespaced symbol table.  Applications calling encoder functions for these three types must provide a namespace (i.e. `com/example/order/line`) in which field names will be assigned integers starting from zero as they are first encountered.  This table must be managed centrally and shared with other endpoints (much like Protobuf IDL `.proto` files must be shared among endpoints).

Symbol tables are simple 7-bit ASCII files listing symbols in field order and are thus strictly append-only for each namespace, to preserve field IDs forever.

* Lines are terminated by LF or CR-LF, stripped when reading;
* Empty lines are ignored;
* Lines starting with '#' are ignored;
* Lines starting with a TAB are symbols in the current namespace;
* Other lines are namespace declarations.

```
# VOF Symbol Table

com/example/orders
	id
	customer
	lines
	total

com/example/orders/lines
	i
	product
	qty
	unit_price
```

In the above example, symbol 'customer' in namespace 'com/example/orders' is ID `1`.

### NDArray

Fixed-size multi-dimensional lists.  This is a list where the first item is a list of dimension sizes, followed by each value from zero-index onward, exactly as many values as the product of all dimension sizes.

For example, a 3D array of size 2x2x2 could be: `[[2,2,2],1,2,3,4,5,6,7,8]`

### Series

Compact representation of a list of `record` where all the same fields are defined (typical of time series data, product price lists, etc.)  In JSON, this is a 2-D Array where the first row selects fields by name and each subsequent row is an Array with just those values.  In CBOR/Binary, this is a flat list where the first item is a list of numeric field IDs and the other items are the values of each record, one after the other (no wrapping necessary).

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

* When possible, records should be sorted by ascending key when buffering the whole list is possible, to facilitate compression.

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

This section suggests a standard for designing HTTP APIs with the VOF data types.

URLs described would be relative to the root of where the API is served (i.e. `https://api.example.com/api/12.1/`) so for example `GET …/users` would mean getting `/api/12.1/users`.

With methods carrying content (`PATCH`, `POST`) should use `Content-Type: application/json` and `X-Content-Type-Options: nosniff` to prevent second-guessing based on contents.

If you need to issue multiple API requests within a few seconds, HTTP/1.1 `keepalive` use is encouraged.

### HTTP Response Codes

| Code                        | Methods        | Notes                                     |
| --------------------------- | -------------- | ----------------------------------------- |
| `200 OK`                    | _all_          | Success with a response body              |
| `201 Created`               | `POST`         | Success with a response body              |
| `400 Bad Request`           | `GET`, `POST`  | Fatal error, don't retry this query as-is |
| `401 Unauthorized`          | _all_          | Authentication failure                    |
| `403 Forbidden`             | _all_          | Authentication valid but insufficient     |
| `404 Not Found`             | `GET`, `PATCH` | Incorrect URL or non-existent ID          |
| `423 Locked`                | _all_          | Record(s) temporarily unavailable         |
| `429 Too Many Requests`     | _all_          | Wait and try again                        |
| `500 Internal Server Error` | _all_          | Wait and try again                        |
| `501 Not Implemented`       | _all_          | Fatal error, don't retry                  |

### Conventions

* Use `decimal` and its derivatives for financial data which requires exact precision (quantities, amounts) and `float64` for ratios and other non-financial data better suited for floating point numbers.
* Record field types may only ever be changed for wire-compatible ones.  For example, `decimal` could become `String`, but not the other way around.
* Generated views/reports should be declared as record types in their module, probably with a `Series` result.
* Variant/Enum/Record use `Capitalized` names.  Dependent records are namespaced in their parent, i.e. `Order.Line` used by `Order`.
* Fields use `snake_case`.  Pluralize lists (i.e. `lines`)
* When naming fields referring to other record types:
  * Use `foo(s)` when embedding instances
  * Use `foo_id(s)` when referring by ID
* Field names with multiple words should go from most to least precise (i.e. prefer `item_qty` over `qty_item`)
* Suffix non-self-describing field names to clarify their type when the value might not be obvious: `_code`, `_id`, `_amt` or `_price`, `_qty`, `_tax`

### GET Parameters

These query string parameters are available for all `GET` requests.  In order to avoid conflicts with field names, all these parameters end with a tilde (`~`).  This also has the benefit of being visually distinctive (i.e. `max~=20` for a result limit).

#### `select~`

(Default: `*`.)  When only a subset of a record's fields are of interest, adding a `select~` query string parameter to any `GET` request filters them at the source.  This is a comma-delimited list of field names, which can take the following forms:

* `*` — Include all fields at this level (required to use `!` exclusions).
* `id` — It is never necessary to request this field explicitly, as it is always included with records.
* `foo` — Regular field to be included.
* `*,!foo` — All fields except `foo`.
* `foo_id` — Reference by ID to be included.
* `foo_id` requested as `foo` or `foo[*]` — Stripping the field's suffix requests that `foo_id` be included _and_ that the referred record be included in `Response.heap`.
* `foo[bar,baz]` — Only include fields `id` (if any), `bar` and `baz` of dependent or referenced field `foo` or `foo_id`.
* `*,foo[*,!bar]` — All fields, except the `bar` field of `foo`.

Example: `GET …/orders?user_id=…&select~=ordered_on,grand_total,lines[qty,unit_price,product[name]]`

#### `prune~`

(Default: none.)  List of a record's fields (expected to be lists of children) to filter based on row filters.  Use `*` to mean "any applicable lists of children."

#### `max~` and `page~`

(Defaults: `max~=100` and `page~=1`)  Restricts results returning multiple records to fewer per call.

#### Row Filters

Use the form `<field>=[<operator>:]<value(s)>` inspired by PostgREST to filter by field value.  For example, `created_on=atleast:20250101` filters out records which were created before 2025-01-01, `id=1234` requires an ID of "1234" and `is_draft=$false` requires that `is_draft` not be truthy.  Appending '!' to a field name negates its operator, like `name!=has:Smith` selects all names _not_ including keyword "Smith".  Filters are additive (all must be met) and fields may be specified more than once.

Available operators (some with synonyms):

| Operator              | Meaning                                                     |
| --------------------- | ----------------------------------------------------------- |
| _none_                | equals exactly                                              |
| `lt`/`under`/`before` | field is less than                                          |
| `lte`/`upto`          | field is less than or equal                                 |
| `gt`/`over`/`after`   | field is greater than                                       |
| `gte`/`atleast`       | field is greater than or equal                              |
| `between`             | inclusive, i.e. `created_on=between:20250101:20251231`      |
| `has`                 | string contains keyword                                     |
| `in(…)`               | exactly one of these values, i.e. `categ_id=in:123:234:345` |

Special values:

| Value    | Meaning                                                  |
| -------- | -------------------------------------------------------- |
| `$true`  | truthy value (`true`, non-zero number, non-empty string) |
| `$false` | falsey value (`false`, zero, empty string)               |

Using filters on children implies that parents without any matching children will not be included.  By default, all children of included parents are included, unless specified in `prune~`.

For example, `…/orders?prune~=lines&date=between:20250101:20251231&lines.product=in(ABC,DEF)` would return orders placed in 2025 which have lines about products ABC or DEF, but each order would only incude lines about products ABC or DEF.

### PATCH Updates

A `PATCH` record is a possibly incomplete copy of an existing record with the primary key specified in the URL and/or in the record itself.  The patch version of a record has the exact same structure as the record itself (like a normal REST `PUT`), with the following additional operations available for convenience:

* Omit any field to leave it unchanged
* Set any field to `Null` to unset its value
* In arrays of records:
  * Unchanged: omit record entirely
  * Add: record without primary key
  * Edit: record with primary key and at least one other field
  * Delete: record with only primary key
* Other arrays are full replacements

```json5
// Example patch on a hypothetical order record
{
  // Simple field updates
  delivered_on: null,
  deliver_by: 20250131,

  // Array replacement (simple values)
  labels: [ "red", "blue" ],
  notify_user_ids: [ 836583, 647684 ],  // Remove previous CC list, add these two

  // Discrete operations on arrays of private child records
  lines: [
    // Line i=1 unchanged
    { i: 2 },  // Delete line i=2
    { i: 3, qty: "1.3", subtotal: "13" },  // New values in line i=3
    { qty: "5", retail_amt: "5.05", subtotal: "25" },  // New line, server-assigned i
    { qty: "4", retail_amt: "1", subtotal: "4" },  // Other new line
  ]
}
```

### Standard Endpoints

Unless specified otherwise, record types offer an endpoint corresponding to its namespace without the global prefix. (i.e. `com/example/orders/accounts` would be `…/orders/accounts`)  Below, `{path}` represents this path (i.e. `orders/accounts`) and `{Record}` the main record type (i.e. "Order").  Some child-only types (i.e. order lines) don't necessarily have endpoints.

Ping endpoint: `GET …/` should return a Response with `status` set to "success".

Simple endpoints:

| Endpoint                    | Request               | Response fields                |
| --------------------------- | --------------------- | ------------------------------ |
| `GET …/{path}/{id}`         | -                     | `heap` with exactly one record |
| `GET …/{path}[?…]`          | -                     | `heap` with records            |
| `POST …/{path}`             | `{Record}` without ID (new) | `affected`               |
| `PATCH …/{path}`            | `{Record}` with ID (existing) | `affected`, `ignored` optional |
| `DELETE …/{path}/{id1}[,…]` | -                     | `affected`, `ignored` optional |

Multiplexed endpoints are on the root path, which is reserved for protocol-level use:

| Endpoint   | Request                               | Response fields       |
| ---------- | ------------------------------------- | --------------------- |
| `POST …/`  | `Heap` of records without IDs (new)   | `affected`            |
| `PATCH …/` | `Heap` of patches with IDs (existing) | `affected`, `ignored` |

When clients POST/PATCH, they should collect records and all their descendants recursively.  Records with old or no modified time should be added as references, dependent and recent records should be included in full.  If the server is missing information to complete the request, the `Response` status should be "partial" or "failed" and the missing records detailed in `ignored` so the client may add the records to their heap and try again.

#### Ref

Qualified reference to a record.  Typically contains a primary key ID and optionally a modification time for sync and/or a message for error reporting (i.e. in a failed/partial `Response` it could explain why one failed).  This is a root-level namespace in a project, i.e. `com/example/ref`.  A project should define a single scalar type for record identity (typically `uint` or `String`) used across all record types, being a surrogate if necessary to internal composite keys.  For example, it could be:

| Field           | Type                 | Notes                       |
| --------------- | -------------------- | --------------------------- |
| `id`            | `uint`               |                             |
| `last_modified` | `timestamp` optional | Last modification timestamp |
| `why`           | `String` optional    | Why the record failed       |

#### Heap

Collection of records and references, thus with 2 fields for each major structure type of a project.  This is a root-level namespace in a project, like `com/example/heap`, structured as:

| Field           | Type              |
| --------------- | ----------------- |
| `orders`        | `Array<Order>`    |
| `ref_orders`    | `Array<Ref>`      |
| `products`      | `Array<Product>`  |
| `ref_products`  | `Array<Ref>`      |
| ...             | ...               |

### Response

Standard structure returned with every HTTP response.  It consists of standard fields, plus one per major structure type.  This is a root-level namespace in a project, like `com/example/response`, structured as:

| Field       | Type                   | Notes                                                        |
| ----------- | ---------------------- | ------------------------------------------------------------ |
| `status`    | `String`               | One of: "success", "partial", "failed"                       |
| `error`     | `String` optional      |                                                              |
| `affected`  | `Heap` optional        | Records which were processed successfully                    |
| `ignored`   | `Heap` optional        | Explanations included for records which couldn't be processed |
| `heap`      | `Heap` optional        | Records referenced by the main record or list                |
| `remaining` | `uint` optional        | If the current result set is limited, how many items follow |
| `orders`    | `OrderResponse`        | Additional fields specific to responses from the Order module(s) |
| ...         | ...                    |                                                                  |

## Implementation Considerations

Encoders are encouraged to use Gzip or Zstd compression for VOF messages exceeding 100-200 bytes.  Decoders can always know the format of VOF data by inspecting the first few bytes:

| First byte(s)       | Unique meaning                  |
|---------------------|---------------------------------|
| 0x1F 0x8B           | Gzip                            |
| 0x28 0xB5 0x2F 0xFD | Zstd                            |
| 0x5B or 0x7B        | JSON (array, object)            |
| 0x80-0xDF           | CBOR (array, map, tag, magic)   |
| 0xEB-0xFF           | VOF Binary (non-numeric, magic) |

### Series

Encoders should use the first record of the list to determine the structure of all records in the list.  They should fail if a subsequent member has extra fields set.  If subsequent members are missing any fields though, encoders should encode `Null` for them in order to keep going.

## Design Compromises

* The `decimal`, `date` and `datetime` types were designed for financial systems based on SQLite and kept here for their compact sizes.
* The `code` type was initially designed as a base 37 `uint`, but the space savings were not worth the implementation complexity.
* The last size of `decimal` is 9 and not 7 in order to match the maximum precision allowed in some other business contexts such as ANSI X12.
