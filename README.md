# VOF

[![license](https://img.shields.io/github/license/vphantom/vof.svg?style=plastic)]()

<!-- [![GitHub release](https://img.shields.io/github/release/vphantom/vof.svg?style=plastic)]() -->

VOF is an API design, type system and serialization specification.  It fills my need to facilitate interoperability between JSON, CBOR, Protocol Buffers and SQLite for business applications.  The VOF types can be serialized in three formats:

* **JSON** — Human-readable, fairly self-documenting but verbose
* **CBOR** — Very compact using CBOR as a low-level format
* **VOF Binary** — Simpler and most compact, but fully custom encoding

All three formats can be used as-is or with Gzip or Zstd compression.

Design goals:

* Easy to implement in a new language (weekend project for a typical subset)
* Low CPU/memory requirements to encode and especially decode
* Space-efficient output size
* Easy versioning with numbered record fields (like Protobuf)
* Application-facing references (de-duplication on the wire and in memory)
* Schema-based (writers and readers agree on types out-of-band)
* Enough explicit type information for inspection of unknown data
* Explicit JSON-CBOR-VOF interoperability (like Protobuf)
* Unambiguous decoding from any specified format and compression scheme

Goals specific to CBOR and VOF Binary:

* Streamable
* Very compact record type

The name "vanilla" was chosen to symbolize the aim to keep the format as simple and generic as possible, thus "Vanilla Object Format" initially when VOF Binary was created, which became "Vanilla Object Framework" as the project grew, and now simply "VOF".

## Version Control Strategy

The format itself allows for very large numeric sizes and makes room for future more complex types with the concept of reserved tags.  This format is thus forward-compatible with future versions.

To help with schema evolution, VOF specifies namespace files to be shared between endpoints to keep symbols reserved forever.  Unlike a true IDL, these files contain no type information.  It is up to endpoints to agree on types out of band (usually in documentation) and to follow the basic rules of backward and forward compatibility:

* Fields must never be repurposed;
* Types may be updated, but only in backwards-compatible ways (i.e. `int` vs `enum`).

### Specification Status

Release Candidate 14 - 2026-04-20

## ROADMAP

- [ ] Test round-trips to try to catch fatal design issues
- [ ] Create data files to help test all implementations

## SPECIFICATIONS

* [JSON-Only Types & APIs](JSON_APIs.md)
* [Full Types & APIs](SPECIFICATION.md)
* [VOF Binary Encoding](BINARY.md)

## IMPLEMENTATIONS

* [OCaml](ocaml/README.md) (JSON/CBOR/Binary, API server utils)
* [Perl 5](perl5/TODO.md) (JSON client only)

## ACKNOWLEDGEMENTS

Graph X Design Inc. https://www.gxd.ca/ sponsored part of this project.

## LICENSE AND COPYRIGHT

Copyright (c) 2023-2026 Stéphane Lavergne <https://github.com/vphantom>

Distributed under the MIT (X11) License:
http://www.opensource.org/licenses/mit-license.php

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
