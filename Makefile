NIM ?= nim
FLAGS += -p:. -p:test/chagashi

.PHONY: all
all: test

.PHONY: test
test:
	if ! test -d test/chagashi; then cd test && git clone https://git.sr.ht/~bptato/chagashi; fi
	if ! test -d test/html5lib-tests; then cd test && git clone https://github.com/html5lib/html5lib-tests.git; fi
	$(NIM) r $(FLAGS) test/test1.nim
	$(NIM) r $(FLAGS) test/tree.nim
	$(NIM) r $(FLAGS) test/tokenizer.nim
	$(NIM) r $(FLAGS) test/tree_charset.nim
	$(NIM) r $(FLAGS) test/tree_misc.nim
