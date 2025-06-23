#!/bin/sh

if ! test "$CHA"
then	test -f ../../cha && CHA=../../cha || CHA=cha
fi

failed=0
for h in *.html *.http
do	case $h in
	cookie.css.http|headers.http) continue;;
	esac
	printf '%s\r' "$h"
	if ! "$CHA" -C config.toml "http://localhost:$1/$h" | diff all.expected -
	then	failed=$(($failed+1))
		printf 'FAIL: %s\n' "$h"
	fi
done
printf '\n'
$CHA -C config.toml -d "http://localhost:$1/stop" >/dev/null
exit "$failed"
