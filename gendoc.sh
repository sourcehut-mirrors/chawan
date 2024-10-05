#!/bin/sh
mkdir -p .obj/doc
for f in chame/*.nim
do	if test "$f" = "chame/htmlparseriface.nim"
	then	nim doc -d:nimdocdummy --outdir:.obj/doc "$f"
	else	nim doc -p:test/chagashi/ --outdir:.obj/doc "$f"
	fi
        sed -i \
          -e '/<\!-- Google fonts -->/,+2d' \
          -e 's/theindex.html/index.html/g' \
          ".obj/doc/$(basename "$f" .nim).html"
done
makehtml() {
	printf '<!DOCTYPE html>
<head>
<meta name=viewport content="width=device-width, initial-scale=1">
<title>%s</title>
</head>
<body>
' "$2"
	cat "$1" | pandoc
	printf '</body>\n'
}
makehtml doc/manual.md "Chame manual" > .obj/doc/manual.html
makehtml doc/.index.md "Chame documentation" > .obj/doc/index.html
