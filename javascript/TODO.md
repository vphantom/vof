# JavaScript

This will be a JSON-only, client-only implementation, structured to facilitate adding the missing pieces later, like the Perl 5 implementation.

```js
export class VOF {
	constructor(tag, ...args) {
		this.tag = tag;
		this.args = args;
		Object.freeze(this);  // CAUTION: does nothing outside of strict mode
		// Also consider Object.seal() and others...
	}
	// toJSON() method which throws or returns a debug representation
}

(() => {
	let i = 0;
	for (const name of [
		'NULL', 'BOOL', 'INT', 'UINT',
		// ...
	]) {
		VOF[name] = i++;
	}
	Object.freeze(VOF);
})();

// new VOF(VOF.INT, 42)
// v instanceof VOF && v.tag === VOF.INT
```
