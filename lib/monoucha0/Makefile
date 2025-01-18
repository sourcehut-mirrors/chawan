NIM ?= nim
TESTDIR ?= /tmp/chagashi_test
FLAGS += --debugger:native --mm:refc

.PHONY: all
all: test

.PHONY: test_basic
test_basic:
	$(NIM) $(FLAGS) r -p:. test/basic.nim
	$(NIM) $(FLAGS) r -p:. -d:monouchaUseOpt=1 test/basic.nim

.PHONY: test_regexonly
test_regexonly:
	$(NIM) $(FLAGS) r -d:lreOnly=1 -p:. test/regexonly.nim
	$(NIM) $(FLAGS) r -d:lreOnly=1 -p:. -d:monouchaUseOpt=1 test/basic.nim

.PHONY: test_manual
test_manual:
	$(NIM) $(FLAGS) r -p:. test/manual.nim
	$(NIM) $(FLAGS) r -p:. -d:monouchaUseOpt=1 test/manual.nim

.PHONY: test_etc
test_etc:
	$(NIM) $(FLAGS) r -p:. test/etc.nim
	$(NIM) $(FLAGS) r -p:. -d:monouchaUseOpt=1 test/etc.nim

.PHONY: test
test: test_basic test_regexonly test_manual test_etc
