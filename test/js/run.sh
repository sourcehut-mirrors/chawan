#!/bin/sh
if ! test "$CHA"
then	test -f ../../cha && CHA=../../cha || CHA=cha
fi
failed=0
for h in *.html
do	printf '%s\r' "$h"
	if ! "$CHA" -dC config.toml "$h" | diff all.expected -
	then	failed=$(($failed+1))
		printf 'FAIL: %s\n' "$h"
	fi
done
printf '\n'
exit "$failed"
