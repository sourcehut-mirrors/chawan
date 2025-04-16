/* This file is dedicated to the public domain.
 *
 * FreeBSD libfetch adapter for Chawan local-CGI. Not much more than a
 * proof of concept, as its functionality is very limited:
 * - Only a few HTTP headers are supported: Accept, Referer, User-Agent.
 *   So e.g. cookies do not work.
 * - No HTTP headers are returned at all.
 * - Content-Type is deduced from the extension in a very simplistic manner.
 * - Redirects are respected, but not reported.
 * - See also: BUGS section in fetch(3).
 *
 * Use cases:
 * - ???
 */

#include <sys/param.h>
#include <stdio.h>
#include <fetch.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>

#define FDIE(x) \
	do { \
		puts("Content-Type: text/plain\r\n"); \
		puts(x); \
		puts(fetchLastErrString); \
		exit(1); \
	} while (0)

#define DIE(x) \
	do { \
		puts("Content-Type: text/plain\r\n\r\n" x); \
		exit(1); \
	} while (0)

int hasext(const char *path)
{
	const char *p = path, *q;

	while ((q = strchr(p, '/')))
		p = q + 1;
	q = strchr(p, '.');
	return !!q;
}

int main(int argc, char **argv)
{
	struct url *u;
	const char *method, *content_type, *p, *np;
	const char *scheme, *username, *password, *host, *port, *path, *query;
	FILE *f;
	size_t len;
	int n, iport = 0;
	char buf[4096];
	size_t prev_inbuf_len = 0;
	size_t inbuf_len = 65536;
	size_t read_len;
	char *inbuf = malloc(inbuf_len);
	char docbuf[4097];
	int has_file_ext = 0;

	if (!inbuf)
		DIE("out of memory");
	if (!(method = getenv("REQUEST_METHOD")))
		DIE("REQUEST_METHOD was not set");
	scheme = getenv("MAPPED_URI_SCHEME");
	host = getenv("MAPPED_URI_HOST");
	if (!scheme || !host)
		DIE("Scheme or host expected");
	username = getenv("MAPPED_URI_USERNAME");
	password = getenv("MAPPED_URI_PASSWORD");
	port = getenv("MAPPED_URI_PORT");
	if (port)
		iport = atoi(port);
	else if (!strcmp(scheme, "http"))
		iport = 80;
	else if (!strcmp(scheme, "https"))
		iport = 443;
	docbuf[0] = '\0';
	path = getenv("MAPPED_URI_PATH");
	strlcat(docbuf, path && *path ? path : "/", sizeof(docbuf));
	has_file_ext = hasext(docbuf);
	query = getenv("MAPPED_URI_QUERY");
	if (query && *query) {
		strlcat(docbuf, "?", sizeof(docbuf));
		strlcat(docbuf, query, sizeof(docbuf));
	}
	u = fetchMakeURL(scheme, host, iport, docbuf, username, password);
	if (!u)
		DIE("Failed to create URL");
	content_type = getenv("CONTENT_TYPE");
	np = getenv("REQUEST_HEADERS");
	while (np) {
		p = np;
		np = strstr(p, "\r\n");
		if (!strncasecmp(p, "User-Agent: ", strlen("User-Agent: "))) {
			p += strlen("User-Agent: ");
			len = np ? np - p : strlen(p);
			if (len >= sizeof(buf))
				DIE("User agent string too long");
			memcpy(&buf[0], p, len);
			buf[len] = '\0';
			setenv("HTTP_USER_AGENT", buf, 1);
		} else if (!strncasecmp(p, "Accept: ", strlen("Accept: "))) {
			p += strlen("Accept: ");
			len = np ? np - p : strlen(p);
			if (len >= sizeof(buf))
				DIE("Accept string too long");
			memcpy(&buf[0], p, len);
			buf[len] = '\0';
			setenv("HTTP_ACCEPT", buf, 1);
		}
		if (np)
			np += 2; /* skip CRLF */
	}
	if (!isatty(STDIN_FILENO)) {
		read_len = inbuf_len - 1 - prev_inbuf_len;
		while ((n = fread(&inbuf[prev_inbuf_len], 1, read_len,
				stdin) == read_len)) {
			if (inbuf_len >= ((size_t)-1) / 2)
				DIE("out of address space");
			prev_inbuf_len = inbuf_len;
			inbuf_len *= 2;
			inbuf = realloc(inbuf, inbuf_len);
			if (!inbuf)
				DIE("out of memory");
			read_len = inbuf_len - 1 - prev_inbuf_len;
		}
	} else {
		n = 0;
	}
	inbuf[n] = '\0';
	f = fetchReqHTTP(u, method, "", content_type, inbuf);
	if (!f)
		FDIE("Failed to open request");
	/* Hack: print a HTML content type if there is no file extension.
	 * If there is one, just let the buffer take care of detecting it. */
	puts(has_file_ext ? "\n" : "Content-Type: text/html\n\n");
	while ((n = fread(buf, 1, sizeof(buf), f)))
		fwrite(buf, 1, n, stdout);
}
