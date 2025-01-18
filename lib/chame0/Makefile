NIM ?= nim
FLAGS += -p:. -p:test/chagashi --import:test/eprint

.PHONY: all
all: test

.PHONY: test
test:
	$(NIM) r $(FLAGS) test/test1.nim
	$(NIM) r $(FLAGS) test/tree.nim
	$(NIM) r $(FLAGS) test/tokenizer.nim
	$(NIM) r $(FLAGS) test/tree_charset.nim
	$(NIM) r $(FLAGS) test/tree_misc.nim

.PHONY: submodule
submodule:
	git submodule update --init
