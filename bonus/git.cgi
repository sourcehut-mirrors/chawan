#!/usr/bin/env -S qjs --std
/* adds clickable links to git log, branch, blame & stash list
 * usage:
 * 0. install QuickJS (https://bellard.org/quickjs)
 * 1. put this script in your CGI directory
 * 2. chmod +x /your/cgi-bin/directory/git.cgi
 * 3. ln -s /your/cgi-bin/directory/git.cgi /usr/local/bin/gitcha
 * 4. run `gitcha log', `gitcha branch', `gitcha blame` or `gitcha stash list'
 * other params work too, but without any special processing. it's still useful
 * for ones that open the pager, like git show; this way you can reload the view
 * with `U'.
 * git checkout and friends are blocked for security & convenience reasons, so
 * it may be best to just alias the pager-opening commands.
 * (if you have ansi2html, it also works with w3m. just set GITCHA_CHA=w3m) */

"use strict";

const gitcha = std.getenv("GITCHA_GITCHA") ?? "gitcha";
if (scriptArgs[0].split('/').pop() == gitcha) {
	const cha = std.getenv("GITCHA_CHA") ?? 'cha';
	const params = encodeURIComponent(scriptArgs.slice(1)
		.map(x => encodeURIComponent(x)).join(' '));
	const [path, _] = os.getcwd();
	const prefix = cha == "w3m" ? '/cgi-bin/' : "cgi-bin:";
	os.exec([cha, `${prefix}git.cgi?params=${params}&path=${path}&prefix=${prefix}`]);
	std.exit(0);
}

const query = {};
for (const p of std.getenv("QUERY_STRING").split('&')) {
	const sp = p.split('=');
	query[decodeURIComponent(sp[0])] = decodeURIComponent(sp[1] ?? '');
}

function startGitCmd(config, params) {
	std.out.puts("Content-Type: text/html\n\n" +
	"<style>form{display:inline} input{margin:0}</style>");
	std.out.flush();
	const [read_fd, write_fd] = os.pipe();
	const [read_fd2, write_fd2] = os.pipe();
	os.exec(["git", ...config, ...params], {
		stdout: write_fd,
		block: false
	});
	os.close(write_fd);
	const libexecDir = std.getenv("CHA_LIBEXEC_DIR") ??
		'/usr/local/libexec/chawan';
	const title = encodeURIComponent('git ' + params.join(' '));
	os.exec([libexecDir + "/ansi2html", "-st", title], {
		stdin: read_fd,
		stdout: write_fd2,
		block: false
	});
	os.close(read_fd);
	os.close(write_fd2);
	return std.fdopen(read_fd2, "r");
}

function runGitCmd(config, params, regex, subfun) {
	const f = startGitCmd(config, params);
	let l;
	while ((l = f.getline()) !== null) {
		console.log(l.replace(regex, subfun));
	}
	f.close();
}

os.chdir(query.path);

const config = ["-c", "color.ui=always", "-c", "log.decorate=short"];
const params = query.params ? decodeURIComponent(query.params).split(' ')
	.map(x => decodeURIComponent(x)) : [];

function cgi(cmd) {
	const cgi0 = `${query.prefix}git.cgi?prefix=${query.prefix}&path=${query.path}`;
	return `${cgi0}&params=${encodeURIComponent(cmd)}`;
}

const GitBranchAllowed = ["-l", "--list", "-a", "--all", "-r", "--remote"];

if (params[0] == "log") {
	const showUrl = cgi("show");
	const re = /[a-f0-9]{7}[a-f0-9]*/g;
	function sub(x) {
		return `<a href='${showUrl}%20${x}'>${x}</a>`;
	}
	runGitCmd(config, params, re, sub);
} else if (params[0] == "blame") {
	const showUrl = cgi("show");
	let cmd = "";
	/* git will give us paths relative to the repo root, so correct that. */
	let [path, _] = os.getcwd();
	let op = "";
	while (path.length > 1) {
		const [s, err] = os.stat(path + "/.git");
		if (!err && (s.mode & os.S_IFMT) == os.S_IFDIR)
			break;
		path = path.substring(0, path.lastIndexOf('/'));
		op += "../";
	}
	if (path[path.length - 1] != '/')
		path += '/';
	/* collect existing flags, but skip commit & file name */
	let flags = params.filter(x => x && x != "-s" && x[0] == '-' && (x[1] != '-' || x[2])).join(' ');
	if (flags)
		flags += ' ';
	const file = params.findLast(x => x[0] != '-');
	cmd = encodeURIComponent(`blame ${flags}%s --`);
	/* silence some useless info */
	params.splice(1, 0, "-s");
	const re = /([a-f0-9]{7}[a-f0-9]*) ([^ ]+)? *([0-9]+)\)/g;
	function sub(_, x, y, z) {
		const f = y ? op + y : file;
		return `<a id=${z} href='${showUrl}%20${x}&backlink=${cmd}%20${f}%20${z}'>${x}</a>`;
	}
	runGitCmd(config, params, re, sub);
} else if (params[0] == "branch" &&
	(params.length == 1 ||
	params.length == 2 && GitBranchAllowed.includes(params[1]))) {
	const logUrl = cgi("log");
	const checkoutUrl = cgi("checkout");
	const re = /^(\s+)(<span style='color: -cha-ansi...;'>)?([\w./-]+)(<.*)?$/g;
	function sub(_, ws, $, name) {
		return `${ws}<a href='${logUrl}%20${name}'>${name}</a>\
 <form method=POST action='${checkoutUrl}%20${name}'><input type=submit value=switch></form>`;
	}
	runGitCmd(config, params, re, sub);
} else if (params[0] == "stash" && params[1] == "list") {
	const showUrl = cgi("show");
	const stashApply = cgi("stash apply");
	const stashDrop = cgi("stash drop");
	const re = /^(stash@\{[0-9]+\})/g;
	function sub(s, n) {
		return `<a href='${showUrl}%20${s}'>${n}</a>\
 <form method=POST action='${stashApply}%20${s}'><input type=submit value=apply></form>` +
` <form method=POST action='${stashDrop}%20${s}'><input type=submit value=drop></form>`;
	}
	runGitCmd(config, params, re, sub);
} else if (params[0] == "show" && query.backlink) {
	const cmds = query.backlink.split(' ');
	const hash = cmds.pop();
	const i = cmds.indexOf('%s');
	const re = /[a-f0-9]{40}/g;
	function sub(x) {
		cmds[i] = x + "~1";
		const cmd = cgi(cmds.join(' '));
		return `<a href='${cmd}#${hash}'>${x}</a>`;
	}
	runGitCmd(config, params, re, sub);
} else {
	const safeForGet = ["show", "diff", "blame", "status"];
	if (std.getenv("REQUEST_METHOD") != "POST" &&
		!safeForGet.includes(params[0])) {
		std.out.puts(`Status: 403\nContent-Type: text/plain\n\nnot allowed`);
		std.out.flush();
		std.exit(1);
	}
	const title = encodeURIComponent('git ' + params.join(' '));
	std.out.puts(`Content-Type: text/x-ansi;title=${title}\n\n`);
	std.out.flush();
	const pid = os.exec(["git", ...config, ...params], {
		block: false,
		stderr: 1
	});
	os.waitpid(pid, 0);
}
