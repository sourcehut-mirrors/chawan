#!/bin/sh
mkdir -p .obj/doc
for f in chame/*.nim
do	if test "$f" = "chame/htmlparseriface.nim"
	then	nim doc -d:nimdocdummy --outdir:.obj/doc "$f"
	else	nim doc --outdir:.obj/doc "$f"
	fi
        sed -i \
          -e '/<\!-- Google fonts -->/,+2d' \
          -e 's/theindex.html/index.html/g' \
          ".obj/doc/$(basename "$f" .nim).html"
done
