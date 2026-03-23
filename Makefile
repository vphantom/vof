help:
	@echo "Available targets: all"

all:	JSON_APIs.md

JSON_APIs.md:	SPECIFICATION.md
	@echo "Writing $@..."
	@grep -v '<!-- adv -->' $< \
		|sed '/^>/d' \
		|sed '/<!-- advanced -->/,/<!-- \/advanced -->/d' \
		|sed 's/<!-- .* -->//g' \
		|sed '1,/^### Units of measure/{s/^\(|[^|]*|[^|]*|\).*/\1/;}' \
		|sed ':a;N;$$!ba;s/\n\n\n\+/\n\n/g' \
		>$@

.PHONY:	help all
