NIM ?= nim
FLAGS ?=
TESTDIR ?= /tmp/chagashi_test

.PHONY: all
all:

$(TESTDIR)/data:
	mkdir -p $(TESTDIR)/data
	cp test/data.tar.xz $(TESTDIR)
	tar xJf $(TESTDIR)/data.tar.xz -C $(TESTDIR)/data

.PHONY: test_basic
test_basic:
	$(NIM) $(FLAGS) r -p:. test/basic.nim

.PHONY: test_data
test_data: $(TESTDIR)/data
	CGS_TESTDIR=$(TESTDIR)/data $(NIM) r -p:. test/data.nim

.PHONY: test
test: test_basic test_data

.PHONY: bench
bench:
	$(NIM) $(FLAGS) r -p:. -d:release test/bench.nim

.PHONY: map
map:
	$(NIM) $(FLAGS) r res/createmap.nim > chagashi/charset_map.nim
