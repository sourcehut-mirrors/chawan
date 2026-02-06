#!/bin/sh
# Needs https://github.com/soimort/translate-shell to work.
# Usage: cgi-bin:trans.cgi?word
# You can also set it as a keybinding (in config.toml):
#
# [page]
# gT = '''
# async () => {
#   if (!pager.currentSelection) {
#     pager.alert("No selection to translate.");
#     return;
#   }
#   const text = await pager.getSelectionText();
#   pager.cursorToggleSelection();
#   pager.loadSubmit(`cgi-bin:trans.cgi?${encodeURIComponent(text)}`);
# }
# '''

# QUERY_STRING is URL-encoded. We decode it using the urldec utility provided
# by Chawan.
TEXT=$(printf '%s\n' "$QUERY_STRING" | "$CHA_LIBEXEC_DIR"/urldec)

# Write a Content-Type HTTP header. The `trans' command outputs plain text,
# but with ANSI escape codes, so we use text/x-ansi.
printf 'Content-Type: text/x-ansi\n'

# We must write a newline here, so Chawan knows that all headers have been
# written and incoming data from now on belongs to the body.
printf '\n'

# Check if the `trans' program exists, and if not, die.
if ! type trans >/dev/null
then	printf "ERROR: translator not found"
	exit 1
fi

# Call the `trans' program. It writes its output to standard out, which
# Chawan's local CGI will read in as the content body.
trans -- "$TEXT"
