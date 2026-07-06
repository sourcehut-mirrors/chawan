NIM ?= nim
FLAGS += -p:. -p:../../src

.PHONY: all
all: test

.PHONY: test
test:
	if ! test -d test/html5lib-tests; then cd test && git clone https://github.com/html5lib/html5lib-tests.git --revision=9329e64694e7835d0dcff9811e22856ef6ad16f9; fi
	$(NIM) r $(FLAGS) test/test1.nim
	$(NIM) r $(FLAGS) test/tree.nim
	$(NIM) r $(FLAGS) test/tokenizer.nim
	$(NIM) r $(FLAGS) test/tree_charset.nim
	$(NIM) r $(FLAGS) test/tree_misc.nim

.PHONY: entity
entity:
	cd chame/res && $(NIM) r genentity.nim >../entity_gen.nim
