NIM ?= nim
TESTDIR ?= /tmp/chagashi_test
FLAGS += --debugger:native

.PHONY: all
all: test

.PHONY: test_basic
test_basic:
	$(NIM) $(FLAGS) r --mm:arc -p:. test/basic.nim

.PHONY: test_regexonly
test_regexonly:
	$(NIM) $(FLAGS) r --mm:arc -d:lreOnly=1 -p:. test/regexonly.nim

.PHONY: test_manual
test_manual:
	$(NIM) $(FLAGS) r --mm:arc -p:. test/manual.nim

.PHONY: test_etc
test_etc:
	$(NIM) $(FLAGS) r --mm:arc -p:. test/etc.nim

.PHONY: test
test: test_basic test_regexonly test_manual test_etc
