# Vanilla Object Format

[![license](https://img.shields.io/github/license/vphantom/vof.svg?style=plastic)]()

<!-- [![GitHub release](https://img.shields.io/github/release/vphantom/vof.svg?style=plastic)]() -->

Really, yet another serialization format?  Yes, but one of the simplest!  This fills a niche use case of ours somewhere between JSON, CBOR and Protocol Buffers with the following goals:

* Easy to implement in a new language (weekend project)
* Low CPU/memory requirements to encode and especially decode
* Smaller output size (even vs JSON+gzip)
* Streamable (unlike Protobuf)
* Compact struct type (unlike CBOR)
* Easy versioning with numbered struct fields (like Protobuf)
* Convention for higher-level types (decimal, datetime, etc.)
* Application-facing references (de-duplication on the wire and in memory)
* Schema-based (writers and readers agree on types out-of-band)
* Enough explicit type information for inspection of unknown data
* Explicit binary-JSON interoperability (like Protobuf)

Thus we have a schema-based format based on very simple types on the wire.  Unlike Protobuf, Thrift, Avro, etc. we do not define an interface description language (IDL) and instead rely on implicit typing, much like how JSON and CBOR APIs are usually documented and implemented in the wild.

The name "vanilla" was chosen to symbolize the aim to keep the format as simple and generic as possible.

## Version Control Strategy

The format itself allows for very large numeric sizes and makes room for future more complex types with the concept of reserved tags.  This format is thus forward-compatible with future versions.

Regarding schema evolution, similarly to Google Protocol Buffers, since readers and writers must agree on a format out of band, basic rules must be followed to ensure good forward and backward compatibility:

* Deprecated fields must never be reused;
* Field types may be updated, but only in backwards-compatible ways (i.e. `int` vs `enum`);
* Field IDs must never be reused.

### Status

**BETA SPECIFICATION, NOT YET IMPLEMENTED**  The selection of high-level types may still change a little bit, but the main decisions have all been finalized.

## ROADMAP

Reference implementations:

- [ ] Update JSON spec with relevant bits added to Binary
- [ ] JS (JSON only)
- [ ] OCaml
- [ ] Perl 5

## SPECIFICATIONS

* [Binary Encoding](binary.md)
* [JSON Encoding](json.md)

## ACKNOWLEDGEMENTS

Graph X Design Inc. https://www.gxd.ca/ sponsored part of this project.

## LICENSE AND COPYRIGHT

Copyright (c) 2023-2024 Stéphane Lavergne <https://github.com/vphantom>

Distributed under the MIT (X11) License:
http://www.opensource.org/licenses/mit-license.php

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
