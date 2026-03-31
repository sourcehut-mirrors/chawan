#!/bin/sh

if test -z "$CHA"
then	test -f ../../cha && CHA=../../cha || CHA=cha
fi

if ! $CHA -Iiso-2022-jp ./x | diff x.expected -
then	exit 1
fi
