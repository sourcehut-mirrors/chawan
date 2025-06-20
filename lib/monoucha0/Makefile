NIM ?= nim
TESTDIR ?= /tmp/chagashi_test
FLAGS += --nimcache:.obj --mm:refc
RFLAGS += $(FLAGS) -d:release -d:lto --debugger:native

.PHONY: all
all: test

.PHONY: test_basic
test_basic:
	$(NIM) $(FLAGS) r -p:. test/basic.nim
	$(NIM) $(RFLAGS) r -p:. test/basic.nim

.PHONY: test_regexonly
test_regexonly:
	$(NIM) $(FLAGS) r -d:lreOnly=1 -p:. test/regexonly.nim
	$(NIM) $(RFLAGS) r -d:lreOnly=1 -p:. test/regexonly.nim

.PHONY: test_manual
test_manual:
	$(NIM) $(FLAGS) r -p:. test/manual.nim
	$(NIM) $(RFLAGS) r -p:. test/manual.nim

.PHONY: test_etc
test_etc:
	$(NIM) $(FLAGS) r -p:. test/etc.nim
#TODO ?	$(NIM) $(RFLAGS) r -p:. test/etc.nim

.PHONY: test
test: test_basic test_regexonly test_manual test_etc

clean:
	rm -r .obj
