#!/bin/sh

if test -z "$CHA"
then	test -f ../../cha && CHA=../../cha || CHA=cha
fi

if ! $CHA -Cconfig.toml ./charsecharset.html | diff charsecharset.expected -
then	exit 1
fi

run() { # $1: labels, $2: file, $3: expected
	if ! $CHA -Cconfig.toml -o encoding.document-charset="$1" ./"$2" | diff "$3" -
	then	echo "error in $2"
		exit 1
	fi
}

run iso-2022-jp x x.expected
run '["utf8", "sjis", "latin1"]' sjis.html sjis.expected
run utf8 latin1.html latin1.expected
