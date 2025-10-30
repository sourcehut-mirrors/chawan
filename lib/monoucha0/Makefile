NIM ?= nim
TESTDIR ?= /tmp/chagashi_test
FLAGS += --debugger:native

.PHONY: all
all: test

.PHONY: test_basic
test_basic:
	$(NIM) $(FLAGS) r --mm:refc -p:. test/basic.nim
	$(NIM) $(FLAGS) r --mm:orc -p:. test/basic.nim

.PHONY: test_regexonly
test_regexonly:
	$(NIM) $(FLAGS) r --mm:refc -d:lreOnly=1 -p:. test/regexonly.nim
	$(NIM) $(FLAGS) r --mm:orc -d:lreOnly=1 -p:. test/regexonly.nim

.PHONY: test_manual
test_manual:
	$(NIM) $(FLAGS) r --mm:refc -p:. test/manual.nim
	$(NIM) $(FLAGS) r --mm:orc -p:. test/manual.nim

.PHONY: test_etc
test_etc:
	$(NIM) $(FLAGS) r --mm:refc -p:. test/etc.nim
	$(NIM) $(FLAGS) r --mm:orc -p:. test/etc.nim

.PHONY: test
test: test_basic test_regexonly test_manual test_etc
