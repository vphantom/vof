# Vanilla Object Format

## Data Types

These are standard (to be preferred to alternatives) but optional (implemented as needed).  They are not distinguished explicitly on the wire: applications agree out-of-band about when to use what, much like Protobuf, Thrift, etc.  As such, types such as decimal and coordinates do not use explicit tags in the CBOR encoding, favoring compactness.  See `BINARY.md` for details of VOF's own binary encoding proposed as slightly more compact than CBOR.

| Type Names        | JSON                                                          |
| ----------------- | ------------------------------------------------------------- |
| `null`            | Null                                                          |
| `bool`            | Boolean                                                       |
| `list`            | Array                                                         |
| `intmap`          | Object                                                        |
| `strmap`          | Object                                                        |
| `variant`/`enum`  | Array[String,values…] / String                                |
| `record`          | Object (keys: names)                                          |
| `series`          | 2D Array (row 0: names)                                       |
| `string`          | String (necessarily UTF-8)                                    |
| `bytes`/`data`    | String base-64 URL encoded                                    |
| `uint`            | Number / String if outside MIN/MAX for float64                |
| `int`/`sint`      | Number / String if outside MIN/MAX for float64                |
| `decimal`/`dec`   | String: optional `-` + 1+ digits + possibly `.` and 1+ digits |
| `ratio`           | String: optional `-` + digits + `/` + digits                  |
| `percent`/`pct`   | String: `decimal` hundredths + `%` (i.e. "50%")               |
| `float`           | Number                                                        |
| `date`/`_on`      | `uint` as `YYYYMMDD`                                          |
| `datetime`/`time` | `uint` as `YYYYMMDDHHMM`                                      |
| `timestamp`       | `int` Epoch                                                   |
| `timespan`/`span` | `list[int,int,int]`                                           |
| `code`            | `string` strictly `[A-Z0-9_]`                                 |
| `language`/`lang` | `code` IETF BCP-47                                            |
| `country`/`cntry` | `code` ISO 3166-1 alpha-2                                     |
| `subdivision`     | `code` ISO 3166-2 alpha-1/3<br />(no country prefix)          |
| `currency`/`curr` | `code` ISO 4217 alpha-3                                       |
| `tax_code`        | `code` "CC[_RRR]_X"<br />ISO 3166-1, ISO 3166-2, acronym      |
| `unit`            | `code` UN/CEFACT Rec. 20                                      |
| `text`            | `strmap` of `lang,string` pairs<br />`string` for just one    |
| `amount`/`price`  | String: `dec`<br />+ optional space and `curr`                |
| `tax`/`tax_amt`   | String: `dec`<br />+ optional space and `curr`<br />+ mandatory space + `tax_code` |
| `quantity`        | String: `dec`<br />+ optional space and `unit`                |
| `ip`              | String: IPv4 or IPv6 notation                                 |

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

A project or API has a root namespace, dot-delimited, i.e. `com.example`.

Variant, Enum and Record types need unique namespaces in singular form, for example: `com.example.order.line`

### Series

Compact representation of a list of `record` where all the same fields are defined (typical of time series data, product price lists, etc.)  In JSON, this is a 2-D Array where the first row selects fields by name and each subsequent row is an Array with just those values.

### Decimal

Necessary for financial data.  In JSON, it must be a string to bypass possible float conversions done by some libraries.

### Date

Calendar date, sortable.  Time zone is outside the scope of this type, derived from context as necessary.  In JSON, a human-friendly `YYYYMMDD` number is used to avoid using strings.

### Datetime

Extends `date` with wall clock time, still sortable and with implicit time zone.  In JSON, a human-friendly `YYYYMMDDHHMM` number is used to avoid using stings.

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

## API Best Practices

This section suggests a standard for designing HTTP APIs with the VOF data types.

URLs described would be relative to the root of where the API is served (i.e. `https://api.example.com/api/12.1/`) so for example `GET …/users` would mean getting `/api/12.1/users`.

With methods carrying content (`PATCH`, `POST`) should use `Content-Type: application/json` and `X-Content-Type-Options: nosniff` to prevent second-guessing based on contents.

If you need to issue multiple API requests within a few seconds, HTTP/1.1 `keepalive` use is encouraged.

### HTTP Response Codes

| Code                        | Methods        | Notes                                        |
| --------------------------- | -------------- | -------------------------------------------- |
| `200 OK`                    | _all_          | Full success with a response body            |
| `400 Bad Request`           | `GET`, `POST`  | Full failure, don't retry this query as-is   |
| `401 Unauthorized`          | _all_          | Authentication failure                       |
| `403 Forbidden`             | _all_          | Authentication valid but insufficient rights |
| `404 Not Found`             | `GET`, `PATCH`, `DELETE` | Incorrect URL or non-existent ID   |
| `429 Too Many Requests`     | _all_          | Wait and try again                           |
| `500 Internal Server Error` | _all_          | Wait and try again                           |
| `501 Not Implemented`       | _all_          | Fatal error, don't retry                     |

### Conventions

* **Reference:** a record with only a primary key and, if applicable, a last modification timestamp.  Where there may be a `foo_id` field in storage, in VOF APIs a `foo` reference field is preferable, as it is interchangeable with an inline instance without type ambiguity.
* Use `decimal` and its derivatives for financial data which requires exact precision (quantities, amounts) and `float64` for ratios and other non-financial data better suited for floating point numbers.
* Record field types may only ever be changed for wire-compatible ones.  For example, `decimal` could become `string`, but not the other way around.
* Generated views/reports should be declared as record types in their module, probably with a `Series` result.
* Variant/Enum/Record use `Capitalized` names.  Dependent records are namespaced in their parent, i.e. `Order.Line` used by `Order`.
* Fields use `snake_case`.  Pluralize lists (i.e. `lines`)
* Field names with multiple words should go from most to least precise (i.e. prefer `item_qty` over `qty_item`)
* Suffix non-self-describing field names to clarify their type when the value might not be obvious: `_code`, `_id`, `_amt` or `_price`, `_qty`, `_tax`

### GET Parameters

These query string parameters are available for all `GET` requests.  In order to avoid conflicts with field names, all these parameters end with a tilde (`~`).  This also has the benefit of being visually distinctive (i.e. `max~=20` for a result limit).

#### `select~`

(Default: `*`)  By default, for GET responses, records are sent with all fields present and with references to other records (i.e. order customers, order line products), and only private child records inlined (i.e. an order's lines).  This parameter allows specifying which fields to include, which record fields to inline and which to attach separately in the `$msg`.  It is a comma-delimited list of field names with some modifiers:

* `*` — Include all fields at this level.
* `!foo` — Exclude field `foo`, only valid after `*`.
* `foo` — Regular field to be included (scalar, reference or inline record).
* `foo()` or `foo(…)` — Expand `foo` referenced record inline.
* `$foo` or `$foo(…)` — If `foo` is a reference, attach the full record in `$msg` (de-duplicated).

Full example: `GET …/orders?user=12345&select~=id,ordered_on,grand_total,lines(qty,unit_price,product(id,name))`

#### `max~` and `page~`

(Defaults: `max~=100` and `page~=1`)  Restricts results returning multiple records to fewer per call.

#### Row Filters

* Format: `field[!]=[operator:]value[,value2…]`
* Appending '!' to a field name negates its operator, like `name!=has:Smith` selects all names which do _not_ include "Smith".
* Filters are additive (all must be true).
* Fields may be used more than once.
* Record field members use '.' separators, i.e. `order.lines.qty`
* Bare record fields match on their primary key, i.e. `order.contact` implies `order.contact.id`

Available operators (some with synonyms):

| Operator              | Meaning                                                  |
| --------------------- | -------------------------------------------------------- |
| _none_                | equals exactly (i.e. `id=1234`)                          |
| `lt`/`under`/`before` | field is less than (i.e. `price=lt:10`)                  |
| `lte`/`upto`          | field is less than or equal                              |
| `gt`/`over`/`after`   | field is greater than                                    |
| `gte`/`atleast`       | field is greater than or equal                           |
| `between`             | inclusive, i.e. `created_on=between:20250101:20251231`   |
| `has`                 | string contains keyword                                  |
| `in(…)`               | exactly one of these values, i.e. `categ=in:123:234:345` |

Special values are prefixed with `'$'` and could include:

| Value        | Meaning                                                    |
| ------------ | ---------------------------------------------------------- |
| `$false`     | `Null`, `false`, `"0"`, number 0, empty string, empty list |
| `$true`      | Any non-false value                                        |
| `$today`     | current date in the field's timezone                       |
| `$now`       | current datetime in the field's timezone                   |

Using filters on children implies that parents without any matching children will not be included.  By default, all direct children of included parents (i.e. order lines) are included.

### PATCH Updates

A `PATCH` record is a possibly incomplete copy of an existing record with the primary key specified in the URL and/or in the record itself.  The patch version of a record has the exact same structure as the record itself (like a normal REST `PUT`), with the following additional operations available for convenience:

| Field Type  | Change         | Encoding                          |
| ----------- | -------------- | --------------------------------- |
| Any         | Unchanged      | Omit entirely                     |
| Any         | Unset          | Set to `Null` explicitly          |
| Record list | Unchanged item | Omit entirely                     |
| Record list | New item       | Record without ID or with new ID  |
| Record list | Edited item    | Record with ID and changed fields |
| Record list | Deleted item   | Reference (record with only ID)   |
| Other lists | Any change     | Full replacement                  |

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

Unless specified otherwise, record types offer an endpoint corresponding to its namespace without the global prefix, in plural form and with forward slash separators. (i.e. `com.example.order.account` would be endpoint `…/orders/accounts`)  Below, `{path}` represents this path (i.e. `orders/accounts`) and `{Record}` the main record type (i.e. "Order").  Some child-only types (i.e. order lines) don't necessarily have endpoints.

Ping endpoint: `GET …/` should return a `$msg` with `text` set to `"Pong!"`.

Simple endpoints:

| Endpoint                    | Request body                  | Response `$msg` fields                  |
| --------------------------- | ----------------------------- | --------------------------------------- |
| `GET …/{path}/{id}`         | -                             | One record in the type's field          |
| `GET …/{path}[?…]`          | -                             | Many records in the type's field        |
| `POST …/{path}`             | `{Record}` without ID (new)   | One ref in the type's field             |
| `PATCH …/{path}`            | `{Record}` with ID (existing) | One ref in the type's field             |
| `DELETE …/{path}/{id1}[,…]` | -                             | If any failed: none deleted, `text` set |

### Message `$msg`

Every HTTP response is a `$msg` record, which consists of a few meta-data fields plus one list field per record type in the project.  This is a root-level namespace, like `com.example.$msg`.

| Field          | Type                | Notes                                                       |
| -------------- | ------------------- | ----------------------------------------------------------- |
| `text`         | `string` optional   | Status details, error explanations                          |
| `remaining`    | `uint` optional     | If the current result set is limited, how many items follow |
| `orders`       | `Order list`        | Records of an example `Order` type                          |
| `orders_sales` | `Order/Sales list`  | Hypothetical sales report rows                              |
| ...            | ...                 |                                                             |

## Implementation Considerations

### Series

Encoders should use the first record of the list to determine the structure of all records in the list.  They should fail if a subsequent member has extra fields set.  If subsequent members are missing any fields though, encoders should encode `Null` for them in order to keep going.

