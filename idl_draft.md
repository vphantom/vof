# IDL

We define our IDL as JSON, to keep implementation simple.  The root is an object in which keys deemed "fields" are configuration directives while others are recursive type definitions.

We inspect the first two characters of keys to determine how to parse their value:

- lower,any or upper,upper: this is a field in the current struct
- otherwise, with '$' prefix: this is a variant
- otherwise, this is a nested struct

Therefore, fields may be `snake_case`, `UPPER_CASE` or even `mixedCase` (though the latter is not recommended).  Variants and structs are `Upper_initialed`.

Namespaces are delimited with period '.' characters.

```json5
// JSON5 example
{
	vof: 1,
	package: "org.example.foo",

	// Foo is a struct with nested types and regular fields
	Foo: {

		// Variant where cases have arguments
		$Result: {
			Ok: [1, "string"],
			Error: [2, "string"],
		},

		// Variant used as an enum
		$Code: {
			UNSPECIFIED: 0,
			OK: 1,
			ERR: 3,
			NOT_FOUND: 404,
		},

		// Fields with their ID and type declarations
		id: [0, "uint"],
		name: [1, "string"],
		allowed_states: [3, "list", "Code"],
		synonyms: [4, "map", "string", ["list", "string"] ],
	},
}
```
