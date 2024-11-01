#!/bin/sh
# Add magnet: links to transmission using transmission-remote.
#
# Usage: place magnet.cgi in your cgi-bin directory (don't forget to set
# the executable bit, e.g. chmod +x magnet.cgi), then add the following line
# to your urimethodmap:
#
# magnet: /cgi-bin/magnet.cgi?%s
#
# Then, set the remote transmission session's address using the
# CHA_TRANSMISSION_ADDRESS environment variable, and if needed, the
# authentication data using CHA_TRANSMISSION_AUTH. Alternatively, uncomment
# the following lines and set them there:

#CHA_TRANSMISSION_ADDRESS=localhost:9091
#CHA_TRANSMISSION_AUTH=username:password

#TODO: add a way to authenticate without exposing the credentials as an
# environment variable

die() {
	printf "Content-Type: text/plain\n\n%s" "$1"
	exit 1
}

html_quote() {
	sed 's/&/&amp;/g;s/</&lt;/g;s/>/&gt;/g;s/'\''/&apos;/g;s/"/&quot;/g'
}


test -n "$QUERY_STRING" || die "URL expected"
type transmission-remote >/dev/null || die "transmission-remote not found"

case "$REQUEST_METHOD" in
GET)	URL_HTML_QUOTED="$(printf '%s' "$QUERY_STRING" | html_quote)"
	printf 'Content-Type: text/html\n\n
<!DOCTYPE HTML>
<HEAD>
<TITLE>Add magnet URL</TITLE>
</HEAD>
<H1>Add magnet URL</H1>
<P>
Add the following magnet URL to transmission?
<PRE>%s</PRE>
<FORM METHOD=POST>
<INPUT TYPE=SUBMIT NAME=ADD_URL VALUE=OK>
<INPUT type=HIDDEN NAME=URL VALUE="%s">
</FORM>
' "$URL_HTML_QUOTED" "$URL_HTML_QUOTED"
	;;
POST)	read line
	case $line in
	'ADD_URL=OK&'*) line="${line#*&}" ;;
	*) die 'Invalid POST 1; this is probably a bug in the magnet script.' ;;
	esac
	case $line in
	URL=*) line="${line#*=}" ;;
	*) die 'Invalid POST 2; this is probably a bug in the magnet script.' ;;
	esac
	line=$(printf '%s\n' "$line" | "$CHA_LIBEXEC_DIR"/urldec)
	auth=$CHA_TRANSMISSION_AUTH
	address=${CHA_TRANSMISSION_ADDRESS:-localhost:9091}
	output=$(transmission-remote "$address" ${auth:+ --auth="$auth"} \
			-a "$line" 2>&1)
	printf 'Content-Type: text/plain\n\n%s' "$output"
	;;
*)	die "Unrecognized HTTP method $HTTP_METHOD" ;;
esac
