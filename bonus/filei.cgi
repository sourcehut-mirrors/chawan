#!/usr/bin/env -S qjs --std
/* show all images in a directory.
 * usage:
 * - put it in your cgi-bin folder
 * - add to ~/.urimethodmap:

filei:	/cgi-bin/filei.cgi

 *   then visit filei:directory for a directory of images
 *
 * - you will notice this only works with absolute paths. as a workaround,
 *   add this to config.toml:

[[siteconf]]
url = '^filei:'
rewrite-url = '''
x => x.pathname[0] != "/" ?
	new URL(`filei:${getenv("PWD")}/${x.pathname}`) :
	undefined
'''

 *   now you can use "cha filei:." to view images in the current dir.
 *
 * TODO:
 * - add zoom functionality to viewer (maybe in JS?)
 * - add some way to open any cached image here
 * - rewrite in Nim & move into Chawan proper (maybe merge with dirlist?)
 */

const path = decodeURI(std.getenv("MAPPED_URI_PATH"));
const viewer = std.getenv("MAPPED_URI_QUERY") == "viewer";
const [stat, err1] = os.stat(path);
switch (stat.mode & os.S_IFMT) {
case os.S_IFREG: {
	if (viewer) {
		std.out.puts("Content-Type: text/html\n\n");
		std.out.puts(`<center><img src=${path}></center>`);
	} else {
		std.out.puts("\n");
		const f = std.open(path, 'rb');
		const buffer = new ArrayBuffer(4096);
		let n;
		while ((n = f.read(buffer, 0, 4096))) {
			std.out.write(buffer, 0, n);
		}
	}
	break;
} case os.S_IFDIR: {
	if (path.at(-1) != '/') {
		const scheme = std.getenv("MAPPED_URI_SCHEME", "filei");
		std.out.puts(`Status: 303
Location: ${scheme}:${path}/\n`);
		std.exit(0)
	}
	std.out.puts("Content-Type: text/html\n\n");
	std.out.puts("<html><body><center>")
	const [files, err2] = os.readdir(path);
	let dirs = "";
	let first = true;
	files.sort((a, b) => {
		const [ai, bi] = [a, b].map(x => parseInt(x.replace(/[^0-9]/g, "")));
		if (!isNaN(ai) && !isNaN(bi))
			return ai - bi;
		return a.localeCompare(b)
	});
	for (const file of files) {
		if (file == '.' || file == '..')
			continue;
		const [stat2, err2] = os.stat(path + file);
		if (!stat2)
			continue;
		switch (stat2.mode & os.S_IFMT) {
		case os.S_IFREG:
			if (!first)
				std.out.puts("<br>\n");
			first = false;
			/* note: the CSS wouldn't be necessary if we had quirks mode... */
			std.out.puts(`<a href='${encodeURIComponent(file)}?viewer'><img height=100% style="height: 100vh" src='${file}'></a>`);
			break;
		case os.S_IFDIR:
			dirs += `<a href='${file}/'>${file}/</a><br>\n`;
			break;
		}
	}
	if (dirs)
		std.out.puts("<p>Subdirs:<p>" + dirs + "\n");
	std.out.puts("</center></body></html>");
	break;
}}
