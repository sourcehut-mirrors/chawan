#!/bin/sh
if test -z "$CHA"
then	test -f ../../cha && CHA=../../cha || CHA=cha
fi

sed -E -e 's/^#([^ ])/\1/;s/^(history = ).*/\1false/' ../../bonus/config.toml >tmp_config.toml
if ! $CHA -Ctmp_config.toml /dev/null | diff /dev/null -
then	rm tmp_config.toml
	exit 1
fi
rm tmp_config.toml

$CHA -Ctest.toml test.test >/dev/null || exit 1

if ! $CHA -Ctest.toml -r 'cmd.custom.b()' 2>&1|diff test3.expected -
then	echo "Custom command test failed"
	exit 1
fi

if ! $CHA -Ctest.toml test2.test2 | diff test2.expected -
then	exit 1
fi

if ! $CHA -Cno-lf-at-eof.toml -V >/dev/null
then	exit 1
fi

if $CHA -Cnul-at-eof.toml -V >/dev/null 2>/dev/null
then	echo "NUL was accepted at EOF"
	exit 1
fi

$CHA -r 'quit()'
