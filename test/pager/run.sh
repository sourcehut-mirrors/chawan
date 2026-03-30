#!/bin/sh
if test -z "$CHA"
then	test -f ../../cha && CHA=../../cha || CHA=cha
fi

sed -E -e 's/^#([^ ])/\1/' ../../bonus/config.toml >"${TMPDIR:-/tmp}"/config.toml
if ! $CHA -C"${TMPDIR:-/tmp}/config.toml" /dev/null | diff /dev/null -
then	exit 1
fi

$CHA -Ctest.toml test.test >/dev/null || exit 1

if ! $CHA -Ctest.toml test2.test2 | diff test2.expected -
then	exit 1
fi

$CHA -r 'quit()'
