#!/bin/sh
if test -z "$CHA"
then	test -f ../../cha && CHA=../../cha || CHA=cha
fi

sed -E ../../bonus/config.toml -e 's/^#([^ ])/\1/' >"${TMPDIR:-/tmp}"/config.toml
if ! $CHA -C"${TMPDIR:-/tmp}/config.toml" /dev/null | diff /dev/null -
then	exit 1
fi
