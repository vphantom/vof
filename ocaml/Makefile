help:
	@echo "Available rules: build clean test"

build:
	@dune build

clean:
	@dune clean

test:
	@rm -rf _coverage bisect*.coverage
	@dune runtest --profile=coverage --instrument-with bisect_ppx --force
	@bisect-ppx-report html
	@bisect-ppx-report summary

.PHONY: help build clean test
