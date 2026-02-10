globalThis.cmd = {
    quit: quit,
    suspend: suspend,
    copyURL: () => {
        if (pager.clipboardWrite(pager.url))
            pager.alert("Copied URL to clipboard.");
        else
            pager.alert("Error; please install xsel or adjust external.copy-cmd");
    },
    copyCursorLink: () => {
        const link = pager.hoverLink;
        if (!link)
            pager.alert("Please move the cursor above a link and try again.");
        else if (pager.clipboardWrite(link))
            pager.alert("Copied URL to clipboard.");
        else
            pager.alert("Error; please install xsel or adjust external.copy-cmd");
    },
    copyCursorImage: () => {
        const link = pager.hoverImage;
        if (!link)
            pager.alert("Please move the cursor above an image and try again.");
        else if (pager.clipboardWrite(link))
            pager.alert("Copied URL to clipboard.");
        else
            pager.alert("Error; please install xsel or adjust external.copy-cmd");
    },
    gotoClipboardURL: () => {
        const s = pager.externCapture(config.external.pasteCmd);
        if (s === null)
            pager.alert("Error; please install xsel or adjust external.paste-cmd");
        else
            pager.loadSubmit(s);
    },
    toggleWrap: () => {
        config.search.wrap = !config.search.wrap;
        pager.alert("Wrap search " + (config.search.wrap ? "on" : "off"));
    },
    loadEmpty: () => pager.load(""),
    webSearch: () => pager.load("br:"),
    addBookmark: () => {
        const url = encodeURIComponent(pager.url);
        const title = encodeURIComponent(pager.title);
        pager.gotoURL(`cgi-bin:chabookmark?url=${url}&title=${title}`);
    },
    openBookmarks: () => {
        pager.gotoURL(`cgi-bin:chabookmark?action=view`, {history: false});
    },
    openHistory: () => {
        pager.gotoURL(pager.getHistoryURL(), {
            contentType: 'text/uri-list;title="History Page"',
            history: false,
            charset: "utf-8"
        });
    },
    reloadBuffer: () => pager.reload(),
    discardBufferPrev: () => pager.discardBuffer(pager.buffer, "prev"),
    discardBufferNext: () => pager.discardBuffer(pager.buffer, "next"),
    enterCommand: () => pager.command(),
    toggleCommandMode: () => {
        if ((pager.commandMode = consoleBuffer != pager.buffer)) {
            if (!line)
                pager.command();
            console.show();
        } else
            console.hide();
    },
    toggleLinkHintsAutoClick: async () => {
        const res = await pager.toggleLinkHints();
        if (res)
            pager.click();
    },
    rightClick: async () => {
        if (!pager.menu) {
            const canceled = await pager.contextMenu();
            if (!canceled)
                return pager.openMenu()
        } else
            pager.closeMenu()
    },
    toggleMenu: () => pager.menu ? pager.closeMenu() : pager.openMenu(),
    viewImage: (_, save) => {
        let contentType = null;
        let url = null;
        if (pager.hoverCachedImage) {
            [url, contentType] = pager.hoverCachedImage.split(' ');
            url = 'file:' + pager.getCacheFile(url, pager.buffer.process);
        } else if (pager.hoverImage)
            url = new Request(pager.hoverImage, {headers: {Accept: "*/*"}});
        if (url)
            pager.gotoURL(url, {contentType: contentType, save: save});
    },
    toggleScripting: () => {
        const buffer = pager.buffer;
        const buffer2 = pager.gotoURL(buffer.url, {
            contentType: buffer.contentType,
            history: buffer.history,
            replace: buffer,
            scripting: !buffer.scripting,
            cookie: buffer.cookie
        });
        if (buffer2)
            buffer2.copyCursorPos(buffer)
    },
    toggleCookie: () => {
        const buffer = pager.buffer;
        pager.gotoURL(buffer.url, {
            contentType: buffer.contentType,
            history: buffer.history,
            replace: buffer,
            scripting: buffer.scripting,
            cookie: !buffer.cookie
        });
        if (buffer2)
            buffer2.copyCursorPos(buffer)
    },
    /* vi G */
    gotoLineOrEnd: n => pager.gotoLine(n ?? pager.numLines),
    /* vim gg */
    gotoLineOrStart: n => pager.gotoLine(n ?? 1),
    /* vi | */
    gotoColumnOrBegin: n => pager.setCursorXCenter((n ?? 1) - 1),
    gotoColumnOrEnd: n => n ? pager.setCursorXCenter(n - 1) : pager.cursorLineEnd(),
    selectOrCopy: n => {
        if (pager.currentSelection)
            cmd.buffer.copySelection();
        else
            pager.cursorToggleSelection(n)
    },
    cursorToggleSelectionLine: n => pager.cursorToggleSelection(n, {selectionType: "line"}),
    cursorToggleSelectionBlock: n => pager.cursorToggleSelection(n, {selectionType: "block"}),
    saveImage: () => cmd.buffer.viewImage(1, true),
    mark: async () => {
        const c = await pager.askChar('m');
        if (c.charCodeAt() != 3) /* ctrl-c */
            pager.setMark(c);
    },
    gotoMark: async () => {
        const c = await pager.askChar('`');
        if (c.charCodeAt() != 3) /* C-c */
            pager.gotoMark(c);
    },
    gotoMarkY: async () => {
        const c = await pager.askChar('`');
        if (c.charCodeAt() != 3) /* C-c */
            pager.gotoMarkY(c);
    },
    copySelection: async () => {
        if (!pager.currentSelection) {
            feedNext();
            return;
        }
        const text = await pager.buffer.getSelectionText();
        const s = text.length != 1 ? "s" : "";
        if (pager.clipboardWrite(text))
            pager.alert(`Copied ${text.length} character${s}.`);
        else
            pager.alert("Error; please install xsel or adjust external.copy-cmd");
        pager.cursorToggleSelection();
    },
    cursorSearchWordForward: async n => {
        const word = await pager.getCurrentWord();
        pager.regex = new RegExp('\\b' + RegExp.escape(word) + '\\b', "g");
        return pager.searchNext(n);
    },
    cursorSearchWordBackward: async n => {
        const word = await pager.getCurrentWord();
        pager.regex = new RegExp('\\b' + RegExp.escape(word) + '\\b', "g");
        return pager.searchPrev(n);
    },
    line: {
        openEditor: () => {
            const res = pager.openEditor(line.text);
            if (res != null) {
                line.end();
                line.clear();
                line.write(res);
            }
        }
    }
}

/* init simple commands */
for (const it of ["cursorLeft", "cursorDown", "cursorUp", "cursorRight",
        "cursorNextWord", "cursorNextViWord", "cursorNextBigWord",
        "cursorWordBegin", "cursorViWordBegin", "cursorBigWordBegin",
        "cursorWordEnd", "cursorViWordEnd", "cursorBigWordEnd",
        "cursorPrevLink", "cursorNextLink", "cursorPrevParagraph",
        "cursorNextParagraph", "cursorTop", "cursorBottom",
        "halfPageDown", "halfPageUp", "halfPageLeft", "halfPageRight",
        "pageDown", "pageUp", "pageLeft", "pageRight", "scrollDown", "scrollUp",
        "scrollLeft", "scrollRight", "click", "searchPrev", "searchNext",
        "centerLineBegin", "raisePageBegin", "lowerPageBegin", "nextPageBegin",
        "previousPageBegin", "centerLine", "raisePage", "lowerPage",
        "cursorToggleSelection", "cursorToggleSelection", "cursorNthLink",
        "cursorRevNthLink"]) {
    cmd[it] = n => pager[it](n);
}

/* pager, no precnum */
for (const it of ["markURL", "redraw", "reshape", "cancel", "toggleSource",
        "nextBuffer", "prevBuffer", "cursorLineBegin", "cursorLineTextStart",
        "cursorLineEnd", "lineInfo", "discardBuffer", "discardBufferTree",
        "cursorMiddleColumn", "cursorLeftEdge", "cursorRightEdge",
        "cursorMiddle", "searchForward", "searchBackward", "isearchForward",
        "isearchBackward", "discardTree", "dupeBuffer", "load", "loadCursor",
        "saveLink", "saveScreen", "saveSource", "editScreen", "editSource",
        "toggleImages", "writeInputBuffer", "showFullAlert",
        "toggleLinkHints", "peek", "peekCursor"]) {
    cmd[it] = () => pager[it]();
}

/* line */
for (const it of ["submit", "backspace", "delete", "cancel", "prevWord",
        "nextWord", "backward", "forward", "clear", "kill", "clearWord",
        "killWord", "begin", "end", "escape", "prevHist", "nextHist"]) {
    cmd.line[it] = () => line[it]();
}

/* backwards compat: cmd.pager and cmd.buffer used to be separate */
cmd.pager = cmd.buffer = cmd;

console.show = () => pager.showConsole();
console.hide = () => pager.hideConsole();
console.clear = () => pager.clearConsole();

/*
 * Util
 */
Util.clamp = function(n, lo, hi) {
    return Math.min(Math.max(n, lo), hi);
}

/*
 * Used as a substitute for int.high.
 * TODO: might want to use Number.MAX_SAFE_INTEGER, but I'm not sure if
 * fromJS for int saturates.  (If it doesn't, just change everything to
 * int64.)
 */
Util.MAX_INT32 = 0xFFFFFFFF;

/*
 * Maximum number of consequent clicks registered.
 * Sort of a product of poor design.
 */
Util.MAX_CLICKS = 3;

Util.HttpLike = ["http:", "https:"];

/*
 * Pager
 */

class Mouse {
    pressed = {}; /* button -> position */
    released = {}; /* button -> position */
    click = {}; /* button -> count - 1 */
    inSelection = false;
    blockTillRelease = false;
    moveType = "none"; /* none, drag, select */

    static SHIFT = 1;
    static CTRL = 2;
    static META = 4;
}

/* private */
function addDefaultOmniRule(name, match, url) {
    const fun = x => url + encodeURIComponent(x.substring(x.indexOf(':')));
    config.addOmniRule(name, match, fun);
}

/* private */
Pager.prototype.init = function(pages, contentType, charset, history, pipe) {
    config.initCommands();
    this.mouse = new Mouse();
    this.commandMode = false;
    this.refreshAllowed = new Set();
    addDefaultOmniRule("ddg", /^ddg:/,
        "https://lite.duckduckgo.com/lite/?kp=-1&kd=-1&q=");
    addDefaultOmniRule("br", /^br:/, "https://search.brave.com/search?q=");
    addDefaultOmniRule("wk", /^wk:/,
        "https://en.wikipedia.org/wiki/Special:Search?search=");
    addDefaultOmniRule("wd", /^wd:/,
        "https://en.wiktionary.org/w/index.php?title=Special:Search&search=");
    addDefaultOmniRule("mo", /^mo:/, "https://mojeek.com/search?q=");
    this.runStartupScript();
    if (pipe) {
        this.loadSubmit("stream:-", {
            contentType: contentType ?? "text/x-ansi"
        });
    }
    const init = {contentType, charset, history};
    for (const page of pages)
        this.loadSubmit(page, init);
    this.showAlerts();
}

/*
 * Emulate vim's \c/\C: override defaultFlags if one is found, then remove
 * it from str.
 * Also, replace \< and \> with \b as (a bit sloppy) vi emulation.
 */
/* private */
Pager.prototype.compileSearchRegex = function(s) {
    const ignoreCaseOpt = config.search.ignoreCase;
    let ignoreCase = ignoreCaseOpt == "ignore";
    let s2 = "";
    let hasUpper = false;
    let hasC = false;
    let quot = false;
    for (const c of s) {
        hasUpper = hasUpper || c != c.toLowerCase();
        if (quot) {
            quot = false;
            if (c == 'c')
                ignoreCase = hasC = true;
            else if (c == 'C') {
                ignoreCase = false;
                hasC = true;
            } else if (c == '<' || c == '>') {
                s2 += '\\b';
            } else
                s2 += '\\' + c;
        } else if (c == '\\') {
            quot = true;
        } else
            s2 += c;
    }
    if (quot)
        s2 += '\\';
    if (!hasC && !hasUpper && ignoreCaseOpt == "auto")
        ignoreCase = true;
    return new RegExp(s2, ignoreCase ? "gui" : "gu");
}

/* public */
Pager.prototype.searchNext = async function(n = 1) {
    const regex = this.regex;
    if (regex) {
        let reverse = this.reverseSearch;
        if (n < 0) {
            n = -n;
            reverse = !reverse;
        }
        const fun = reverse ? "cursorPrevMatch" : "cursorNextMatch";
        const wrap = config.search.wrap;
        /* TODO probably we should add a separate keymap for menu/select */
        if (this.menu)
            return this.menu[fun](this.regex, wrap, true, n);
        const buffer = this.buffer;
        buffer.markPos0();
        await buffer[fun](regex, wrap, true, n);
        buffer.markPos();
    } else
        this.alert("No previous regular expression");
}

/* public */
Pager.prototype.searchPrev = function(n = 1) {
    return this.searchNext(-n);
}

/* public */
Pager.prototype.searchForward = async function(reverse = false) {
    const text = await this.setLineEdit("search", reverse ? "?" : "/");
    if (text == null)
        return;
    if (text != "") {
        try {
            this.regex = this.compileSearchRegex(text);
        } catch (e) {
            this.alert("Invalid regex: " + e.message);
        }
    }
    this.reverseSearch = reverse;
    this.searchNext();
}

/* public */
Pager.prototype.searchBackward = function() {
    return this.searchForward(true);
}

/* public */
Pager.prototype.isearchForward = async function(reverse = false) {
    const buffer = this.buffer;
    if (this.menu || buffer?.select) {
        /* isearch doesn't work in menus. */
        this.searchForward(reverse)
    } else if (buffer) {
        buffer.pushCursorPos()
        buffer.markPos0()
        const text = await this.setLineEdit("search", reverse ? "?" : "/", {
            update: async () => {
                const iter = this.isearchIter = (this.isearchIter ?? 0) + 1;
                const text = line.text;
                if (text != "") {
                    try {
                        this.iregex = this.compileSearchRegex(text);
                    } catch (e) {
                        this.iregex = e.message;
                    }
                    this.regex = null;
                }
                buffer.popCursorPos(true);
                buffer.pushCursorPos();
                const re = this.iregex;
                if (re instanceof RegExp) {
                    buffer.highlight = true; /* TODO private variable */
                    let wrap = config.search.wrap;
                    const cx = buffer.cursorx;
                    const cy = buffer.cursory;
                    const iface = buffer.iface;
                    if (iface != null) {
                        const fun = reverse ? "findPrevMatch" : "findNextMatch";
                        const [x, y, w] = await iface[fun](re, cx, cy, wrap, 1);
                        if (this.isearchIter === iter)
                            buffer.onMatch(x, y, w, false);
                    }
                }
            }
        });
        if (text == null) { /* canceled */
            delete this.isearchIter;
            this.iregex = null;
            buffer.popCursorPos();
        } else {
            delete this.isearchIter;
            if (text == "" && !this.regex) {
                buffer.popCursorPos()
            } else {
                if (text != "") {
                    if (typeof this.iregex === "string")
                        this.alert("Invalid regex: " + this.iregex);
                    else
                        this.regex = this.iregex;
                } else
                    this.searchNext()
                this.reverseSearch = reverse;
                buffer.markPos()
                await buffer.sendCursorPosition()
            }
        }
        const iface = buffer.iface;
        if (iface != null)
            iface.clearSearchHighlights()
    }
}

/* public */
Pager.prototype.isearchBackward = function() {
    return this.isearchForward(true);
}

/* Reuse the line editor as an alert message viewer. */
/* public */
Pager.prototype.showFullAlert = function() {
    const str = this.lastAlert;
    if (str != "")
        this.setLineEdit("alert", "", {current: str});
}

/*
 * Check if the user is trying to go to an anchor of the current buffer.
 * If yes, the caller need not call gotoURL.
 */
/* private */
Pager.prototype.gotoURLHash = function(request, current) {
    let url;
    if (request instanceof URL)
        url = request;
    else {
        if (request.method != "GET")
            return false;
        url = new URL(request.url);
    }
    if (current?.iface == null || url.hash == "")
        return false;
    /* check if only hash changed */
    const anchor = url.hash.substring(1);
    url.hash = current.url.hash;
    if (current.url + "" != url + "")
        return false;
    current.iface.gotoAnchor(anchor, false, false).then(([x, y, click]) => {
        if (y >= 0) {
            const nc = this.dupeBuffer2(current, url);
            nc.setCursorXYCenter(x, y);
        } else
            this.alert("Anchor #" + anchor + " not found");
    });
    return true;
}

/*
 * When the user has passed a partial URL as an argument, they might've meant
 * either:
 * - file://$PWD/<file>
 * - https://<url>
 * So we attempt to load both, and see what works.
 */
/* public */
Pager.prototype.loadSubmit = function(url, init) {
    let url0;
    try {
        url0 = this.omniRewrite(url);
    } catch (e) {
        this.alert(`Exception in omni-rule: ${e} ${e.stack}`);
        return;
    }
    const first = URL.parse(url0);
    if (first != null) {
        if (!this.gotoURLHash(first, this.buffer))
            this.gotoURL(first, init);
        return;
    }
    const urls = Util.expandPath(url0);
    if (urls.length == 0)
        return;
    let retry = null;
    const prependScheme = config.network.prependScheme;
    if (prependScheme != "" && urls[0] != '/')
        retry = URL.parse(prependScheme + urls);
    const local = Util.encodeURIPath(urls);
    const cdir = "file:" + Util.encodeURIPath(Util.getcwd()) + "/";
    let url1 = URL.parse(local, cdir);
    if (url1 == null) {
        url1 = retry;
        retry = null;
    }
    if (url1 != null)
        this.gotoURL(url1, {...init, retry: retry});
    else
        this.alert("Invalid URL " + urls);
}

/* Open a URL prompt. */
/* public */
Pager.prototype.load = async function(url = null) {
    if (url == null) {
        if (!this.buffer)
            return;
        url = this.buffer.url;
    }
    const res = await this.setLineEdit("location", "URL: ", {current: url});
    if (res)
        this.loadSubmit(res);
}

/* public */
Pager.prototype.loadCursor = function() {
    return this.load(this.hoverLink || this.hoverImage);
}

/* public */
/* Reload the page in a new buffer, then kill the previous buffer. */
Pager.prototype.reload = function() {
    const old = this.buffer;
    if (!old)
        return;
    const buffer = this.gotoURL(old.url, {
        contentType: old.contentType,
        replace: old,
        history: old.history,
        charset: old.charsetOverride
    })
    buffer.copyCursorPos(old);
}

/* public */
Pager.prototype.discardTree = function(buffer = this.buffer) {
    while (buffer != null) {
        const next = buffer.next;
        this.deleteContainer(buffer, null);
        buffer = next;
    }
}

/* public */
Pager.prototype.dupeBuffer = function() {
    this.dupeBuffer2(this.buffer, this.buffer.url)
}

/* public */
Pager.prototype.traverse = function(dir) {
    this.navDirection = dir;
    const buffer = this.buffer;
    if (buffer == null)
        return false;
    const next = buffer.find(dir);
    if (next == null)
        return false;
    this.setContainer(next);
    return true;
}

/* public */
Pager.prototype.prevBuffer = function() {
    return this.traverse("prev");
}

/* public */
Pager.prototype.nextBuffer = function() {
    return this.traverse("next");
}

/* public */
Pager.prototype.command = async function() {
    const text = await this.setLineEdit("command", "COMMAND: ");
    if (text != null) {
        try {
            console.log(this.evalCommand(text));
        } catch (e) {
            console.log(e + '\n' + e.stack);
        }
        if (this.commandMode)
            return this.command();
    } else
        this.commandMode = false;
}

/* public */
Pager.prototype.gotoLine = async function(n) {
    const buffer = this.buffer;
    const target = this.menu ?? buffer?.select ?? buffer;
    if (!target)
        return;
    if (n === undefined) {
        const text = await this.setLineEdit("gotoLine", "Goto line: ");
        if (text != null)
            return this.gotoLine(text);
    }
    if (typeof n === "number")
        n--; /* gotoLine is 1-indexed */
    else {
        n = n + "";
        if (n.length == 0)
            return;
        if (n[0] == '^')
            n = 0;
        else if (n[0] == '$')
            n = Util.MAX_INT32;
        else
            n = parseInt(n) - 1;
        if (isNaN(n)) {
            this.alert("invalid line number");
            return;
        }
    }
    this.markPos0();
    target.setCursorY(n);
    this.markPos();
}

Pager.prototype.peek = function() {
    const buffer = this.buffer;
    if (buffer != null)
        this.alert(buffer.url);
}

/* private */
Pager.prototype.toggleLinkHints = async function() {
    this.markPos0();
    const urls = await this.showLinkHints();
    if (urls.length == 0) {
        this.alert("No links on page");
        return false;
    }
    const chars = config.input.linkHintChars;
    function hint(n) {
        let tmp = [];
        for (n--; n >= 0; n = Math.floor(n / chars.length) - 1)
            tmp.push(chars[n % chars.length]);
        return tmp.reverse().join("");
    }
    const map = {};
    let offset = Math.floor((urls.length + chars.length - 2) / (chars.length - 1));
    for (let i = 0, j = offset; i < urls.length; i++, j++) {
        let h = hint(j);
        let it = map;
        for (let k = 0, L = h.length - 1; k < L; k++)
            it = it[h[k]] ??= {};
        urls[i].leaf = true;
        it[h.at(-1)] = urls[i];
    }
    let s = "";
    let it = map;
    let alert = true;
    while (it && !it.leaf) {
        const c = await this.askChar(s);
        if (c == '\b' || c == '\x7f') {
            if (s.length == 0) {
                alert = false;
                break;
            }
            s = s.substring(0, s.length - 1);
            it = map;
            for (const c2 of s)
                it = it[c2];
        } else if (c == '\x03') {
            alert = false;
            break;
        } else {
            it = it[c];
            s += c;
        }
    }
    this.hideLinkHints();
    if (it?.leaf) {
        this.setCursorXY(it.x, it.y);
        this.markPos();
        return true;
    } else if (alert)
        this.alert("No such hint");
    return false;
}

/* private */
Pager.prototype.lineInfo = function() {
    const buffer = this.buffer;
    const iface = buffer?.iface;
    if (iface == null)
        return;
    const x0 = buffer.cursorx;
    const y0 = buffer.cursory;
    const x = x0 + 1;
    const y = y0 + 1;
    const numLines = buffer.numLines;
    const perc = numLines == 0 ? 100 : Math.floor(100 * y / numLines);
    const w = buffer.currentLineWidth();
    const b = iface.cursorBytes(y0, x0);
    this.alert(`line ${y}/${numLines} (${perc}%) col ${x}/${w} (byte ${b})`);
}

const MenuMap = [
    ["Select text              (v)", cmd.selectOrCopy],
    ["Previous buffer          (,)", cmd.prevBuffer],
    ["Next buffer              (.)", cmd.nextBuffer],
    ["Discard buffer           (D)", cmd.discardBuffer],
    null,
    ["Copy page URL          (M-y)", cmd.copyURL],
    ["Copy link               (yu)", cmd.copyCursorLink],
    ["View image               (I)", cmd.viewImage],
    ["Copy image link         (yI)", cmd.copyCursorImage],
    ["Reload                   (U)", cmd.reloadBuffer],
    null,
    ["Save link             (sC-m)", cmd.saveLink],
    ["View source              (\\)", cmd.toggleSource],
    ["Edit source             (sE)", cmd.sourceEdit],
    ["Save source             (sS)", cmd.saveSource],
    null,
    ["Linkify URLs             (:)", cmd.markURL],
    ["Toggle images          (M-i)", cmd.toggleImages],
    ["Toggle JS & reload     (M-j)", cmd.toggleScripting],
    ["Toggle cookie & reload (M-k)", cmd.toggleCookie],
    null,
    ["Bookmark page          (M-a)", cmd.addBookmark],
    ["Open bookmarks         (M-b)", cmd.openBookmarks],
    ["Open history           (C-h)", cmd.openHistory],
];

/* public */
Pager.prototype.openMenu = async function(x = null, y = null) {
    const buffer = this.buffer;
    x = Math.max(x ?? buffer?.acursorx, 0);
    y = Math.max(y ?? buffer?.acursory, 0);
    const options = MenuMap.map(x => x ? x[0] : null);
    if (buffer?.currentSelection != null)
        options[0] = "Copy selection           (y)"
    const selected = await new Promise(resolve => {
        this.menu = new Select(options, -1, x, y,
                               this.bufWidth, this.bufHeight, resolve);
    });
    pager.menu = null;
    if (selected != -1)
        MenuMap[selected][1]();
    if (buffer?.iface != null)
        buffer.iface.queueDraw();
}

/* public */
Pager.prototype.closeMenu = function() {
    const menu = this.menu;
    if (menu != null) {
        this.menu = null;
        return menu.cancel();
    }
}

/* public */
Pager.prototype.openEditor = function(input) {
    let tmpf = this.getTempFile();
    Util.mkdir(config.external.tmpdir, 0o700);
    input += '\n';
    try {
        writeFile(tmpf, input, 0o600);
    } catch (e) {
        this.alert("failed to write temporary file");
        return null;
    }
    const cmd = this.getEditorCommand(tmpf);
    if (cmd == "") {
        this.alert("invalid external.editor command");
        return null;
    }
    this.extern(cmd);
    let res = readFile(tmpf, input);
    Util.unlink(tmpf);
    if (res != null && res.at(-1) == '\n')
        res = res.substring(0, res.length - 1);
    return res;
}

/* private */
Pager.prototype.handleMouseInput = async function(input) {
    const mouse = this.mouse;
    if (mouse.blockTillRelease) {
        if (input.t != "release")
            return;
        mouse.blockTillRelease = false;
    }
    const button = input.button;
    const [pressedX, pressedY] = mouse.pressed[button] ?? [-1, -1];
    let buffer = this.buffer;
    const select = this.menu ?? buffer?.select;
    if (select != null) {
        /* one off because of border */
        const y = select.fromy + input.y - select.y - 1;
        let inside =
            select.y + 1 <= input.y && input.y < select.y + select.height - 1 &&
            select.x + 1 <= input.x && input.x < select.x + select.width - 1;
        let outside =
            select.y > input.y || input.y >= select.y + select.height &&
            select.x > input.x || input.x >= select.x + select.width;
        switch (button) {
        case "right":
            if (!inside)
                select.unselect();
            else if (input.x != pressedX && input.y != pressedY) {
                /*
                 * Prevent immediate movement/submission in case the menu
                 * appeared under the cursor.
                 */
                select.setCursorY(y);
            }
            if (input.t == "press") {
                /*
                 * Do not include borders, so that a double right click
                 * closes the menu again.
                 */
                if (!inside) {
                    mouse.blockTillRelease = true;
                    select.cursorLeft();
                }
            } else if (input.t == "release") {
                if (inside && (input.x != pressedX || input.y != pressedY))
                    select.click();
                else if (outside)
                    select.cursorLeft();
            }
            break;
        case "left":
            if (input.t == "press") {
                if (outside) { /* clicked outside the select */
                    mouse.blockTillRelease = true;
                    select.cursorLeft();
                }
            } else if (input.t == "release") {
                if (input.x == pressedX && input.y == pressedY && inside) {
                    /* clicked inside the select */
                    select.setCursorY(y);
                    select.click();
                }
            }
            break;
        }
    } else if (buffer != null) {
        switch (button) {
        case "left":
            switch (input.t) {
            case "move":
                if (mouse.click[button] < 1)
                    break;
                switch (mouse.moveType) {
                case "none":
                    if (pressedY == input.y) {
                        mouse.moveType = "select";
                        if (!buffer.currentSelection?.mouse)
                            await buffer.startSelection("normal", true);
                        buffer.setAbsoluteCursorXY(input.x, input.y);
                    } else
                        mouse.moveType = "drag";
                    break;
                case "select":
                    buffer.setAbsoluteCursorXY(input.x, input.y);
                    break;
                }
                break;
            case "release":
                if (buffer.currentSelection?.mouse) {
                    mouse.inSelection = true;
                    if (this.osc52Primary) {
                        const text = await buffer.getSelectionText();
                        this.clipboardWrite(text, false);
                    }
                } else if (pressedX == input.x && pressedY == input.y &&
                           input.y < buffer.height) {
                    const px = buffer.cursorx;
                    const py = buffer.cursory;
                    buffer.setAbsoluteCursorXY(input.x, input.y);
                    if (px == buffer.cursorx && py == buffer.cursory)
                        buffer.click(mouse.click[button]);
                }
                mouse.moveType = "none";
                break;
            case "press":
                if (buffer.currentSelection?.mouse)
                    buffer.clearSelection();
                break;
            }
            break;
        case "middle":
            if (input.t == "release" && input.x == pressedX &&
                input.y == pressedY && input.y < buffer.height) {
                this.discardBuffer(buffer);
            }
            break;
        case "right":
            if (input.t == "press" && input.y < buffer.height) {
                let canceled = false;
                if (buffer.currentSelection == null &&
                    !(input.mods & Mouse.META)) {
                    buffer.setAbsoluteCursorXY(input.x, input.y);
                    canceled = await buffer.contextMenu();
                }
                if (!canceled) {
                    this.openMenu(input.x, input.y);
                    this.menu.unselect();
                }
            }
            break;
        case "thumbInner":
            if (input.t == "press")
                this.prevBuffer();
            break;
        case "thumbTip":
            if (input.t == "press")
                this.nextBuffer();
        }
    }
    if (!mouse.blockTillRelease) {
        switch (button) {
        case "left":
            if (input.t == "release") {
                if (this.mouse.inSelection) {
                    this.mouse.inSelection = false;
                } else if (input.y == this.bufHeight &&
                           pressedX == input.x && pressedY == input.y) {
                    this.load();
                } else if (input.y >= this.bufHeight - 1 &&
                           pressedY == input.y) {
                    const dcol = input.x - pressedX;
                    if (dcol <= -2)
                        this.nextBuffer();
                    else if (dcol >= 2)
                        this.prevBuffer();
                } else if (pressedX != -1 && pressedY != -1) {
                    const dcol = input.x - pressedX;
                    const drow = input.y - pressedY;
                    if (dcol > 0)
                        this.scrollLeft(dcol);
                    else
                        this.scrollRight(-dcol);
                    if (drow > 0)
                        this.scrollUp(drow);
                    else
                        this.scrollDown(-drow);
                }
            }
            break;
        case "right":
            if (input.t == "release" && pressedX == input.x &&
                pressedY == this.bufHeight) {
                this.loadCursor();
            }
            break;
        case "middle":
            if (input.t == "release" && pressedX == input.x &&
                pressedY == this.bufHeight) {
                this.load("");
            }
            break;
        case "wheelUp":
            if (input.t == "press")
                this.scrollUp(config.input.wheelScroll);
            break;
        case "wheelDown":
            if (input.t == "press")
                this.scrollDown(config.input.wheelScroll);
            break;
        case "wheelLeft":
            if (input.t == "press")
                this.scrollLeft(config.input.sideWheelScroll);
            break;
        case "wheelRight":
            if (input.t == "press")
                this.scrollRight(config.input.sideWheelScroll);
            break;
        }
        switch (input.t) {
        case "press":
            mouse.pressed[button] = [input.x, input.y];
            const [releasedX, releasedY] =
                mouse.released[button] ?? [-1, -1];
            if (input.x == releasedX && input.y == releasedY) {
                mouse.click[button] ??= 0;
                if (++mouse.click[button] >= Util.MAX_CLICKS)
                    mouse.click[button] = 0;
            }
            break;
        case "release":
            if (pressedX != input.x || pressedY != input.y)
                mouse.click[button] = 0;
            mouse.released[button] = mouse.pressed[button];
            mouse.pressed[button] = [-1, -1];
            break;
        }
    }
    this.queueStatusUpdate();
    this.handleEvents();
}

/* private */
Pager.prototype.handleInput = async function(t, mouseInput) {
    const line = globalThis.line;
    let paste = false;
    switch (t) {
    case "paste": paste = true; case "keyEnd":
        if (this.fulfillAsk()) {
            this.queueStatusUpdate();
        } else if (line != null) {
            if (paste || line.escNext) {
                line.escNext = false;
                this.writeInputBuffer();
            } else {
                const map = config.line;
                const p = this.evalInputAction(map, 0);
                if (map.keyLast == 0) {
                    await p;
                    this.updateReadLine();
                }
            }
        } else if (paste) {
            const p = this.setLineEdit("location", "URL: ");
            this.writeInputBuffer();
            const res = await p;
            if (res)
                this.loadSubmit(res);
        } else if (this.updateNumericPrefix()) {
            this.queueStatusUpdate();
        } else {
            const map = config.page;
            const p = this.evalInputAction(map, this.arg0);
            /*
             * We must queue the status update before the await in order to
             * avoid the following situation:
             * 1. action calls alert()
             * 2. action awaits something
             * 3. action finishes
             * 4. now we return after the await, but the status update has
             *    already been shown in another event cycle, so the alert
             *    disappears.
             * (Probably there is a better design for all this.)
             */
            this.queueStatusUpdate();
            if (map.keyLast == 0) {
                this.precnum = 0;
                await p;
                this.handleEvents();
            }
        }
        break;
    case "mouse":
        return this.handleMouseInput(mouseInput);
    }
}

/* private */
Pager.prototype.redirect = async function(buffer, request) {
    const redirectDepth = buffer.redirectDepth;
    if (redirectDepth < config.network.maxRedirect) {
        const url = new URL(request.url);
        const requestProto = url.protocol;
        const bufferProto = buffer.url.protocol;
        if (bufferProto != requestProto && bufferProto != "cgi-bin:") {
            if (requestProto == "cgi-bin:") {
                this.alert("Blocked redirection attempt to " + url);
                return;
            }
            if (!(Util.HttpLike.includes(bufferProto) &&
                  Util.HttpLike.includes(requestProto))) {
                const x = await this.ask("Warning: switch protocols? " + url);
                if (!x)
                    return;
            }
        }
        this.numload--;
        const save = buffer.save;
        if (save || !this.gotoURLHash(request, buffer)) {
            const nc = this.gotoURL(request, {
                history: buffer.history,
                save: save,
                redirectDepth: redirectDepth + 1,
                referrer: buffer
            });
            if (nc != null) {
                const replace = buffer.unsetReplace();
                this.replace(buffer, nc);
                if (replace != null)
                    nc.setReplace(replace);
                nc.setLoadInfo("Redirecting to " + url);
            }
        }
    } else {
        this.alert("Error: maximum redirection depth reached")
        this.deleteContainer(container, buffer.find("any"))
    }
}

/*
 * Buffer
 *
 * TODO: all logic in Container should be moved to Buffer and
 * BufferInterface, then we can make Buffer a JS-only class.
 */

/* public */
Buffer.prototype.cursorDown = function(n = 1) {
    this.setCursorY(this.cursory + n);
}

/* public */
Buffer.prototype.cursorUp = function(n = 1) {
    this.setCursorY(this.cursory - n);
}

/* public */
Buffer.prototype.cursorLeft = function(n = 1) {
    this.setCursorX(this.cursorFirstX() - n);
}

/* public */
Buffer.prototype.cursorRight = function(n = 1) {
    this.setCursorX(this.cursorLastX() + n);
}

/* public */
Buffer.prototype.scrollDown = function(n = 1) {
    const H = this.numLines;
    const y = Math.min(this.fromy + this.height + n, H) - this.height;
    if (y > this.fromy) {
        this.setFromY(y);
        const dy = this.fromy - this.cursory;
        if (dy > 0)
            this.cursorDown(dy);
    } else
        this.cursorDown(n);
}

/* public */
Buffer.prototype.scrollUp = function(n = 1) {
    const y = Math.max(this.fromy - n, 0);
    if (y < this.fromy) {
        this.setFromY(y);
        const dy = this.cursory - this.fromy - this.height + 1;
        if (dy > 0)
            this.cursorUp(dy);
    } else
        this.cursorUp(n);
}

/* public */
Buffer.prototype.scrollRight = function(n = 1) {
    const msw = this.maxScreenWidth();
    const x = Math.min(this.fromx + this.width + n, msw) - this.width;
    if (x > this.fromx)
        this.setFromX(x);
}

/* public */
Buffer.prototype.scrollLeft = function(n = 1) {
    const x = Math.max(this.fromx - n, 0);
    if (x < this.fromx)
        this.setFromX(x);
}

/* public */
Buffer.prototype.pageDown = function(n = 1) {
    const delta = this.height * n;
    this.setFromY(this.fromy + delta);
    this.setCursorY(this.cursory + delta);
    this.restoreCursorX();
}

/* public */
Buffer.prototype.pageUp = function(n = 1) {
    this.pageDown(-n);
}

/* public */
Buffer.prototype.pageLeft = function(n = 1) {
    this.setFromX(this.fromx - this.width * n);
}

/* public */
Buffer.prototype.pageRight = function(n = 1) {
    this.setFromX(this.fromx + this.width * n);
}

/* I am not cloning the vi behavior of e.g. 2^D setting paging size because
 * it is counter-intuitive and annoying. */
/* public */
Buffer.prototype.halfPageDown = function(n = 1) {
    const delta = (this.height + 1) / 2 * n;
    this.setFromY(this.fromy + delta);
    this.setCursorY(this.cursory + delta);
    this.restoreCursorX();
}

/* public */
Buffer.prototype.halfPageUp = function(n = 1) {
    this.halfPageDown(-n);
}

/* public */
Buffer.prototype.halfPageLeft = function(n = 1) {
    this.setFromX(this.fromx - (this.width + 1) / 2 * n);
}

/* public */
Buffer.prototype.halfPageRight = function(n = 1) {
    this.setFromX(this.fromx + (this.width + 1) / 2 * n);
}

/* public */
Buffer.prototype.cursorTop = function(n = 1) {
    this.markPos0();
    this.setCursorY(this.fromy + Util.clamp(n - 1, 0, this.height - 1));
    this.markPos();
}

/* public */
Buffer.prototype.cursorMiddle = function() {
    this.markPos0();
    this.setCursorY(this.fromy + (this.height - 2) / 2);
    this.markPos();
}

/* public */
Buffer.prototype.cursorBottom = function(n = 1) {
    this.markPos0();
    this.setCursorY(this.fromy + this.height - Util.clamp(n, 0, this.height));
    this.markPos();
}

/* public */
Buffer.prototype.cursorLeftEdge = function() {
    this.setCursorX(this.fromx);
}

/* public */
Buffer.prototype.cursorMiddleColumn = function() {
    this.setCursorX(this.fromx + (this.width - 2) / 2);
}

/* public */
Buffer.prototype.cursorRightEdge = function() {
    this.setCursorX(this.fromx + this.width - 1);
}

/* private */
Buffer.prototype.onMatch = function(x, y, w, refresh) {
    const iface = this.iface;
    if (y >= 0) {
        this.setCursorXYCenter(x, y, refresh);
        if (this.highlight) {
            iface.clearSearchHighlights();
            iface.addSearchHighlight(x, y, x + w - 1, y);
            this.highlight = false;
        }
    } else if (this.highlight) {
        iface.clearSearchHighlights();
        this.highlight = false;
    }
}

/* private */
Buffer.prototype.cursorNextMatch = async function(re, wrap, refresh, n) {
    if (this.select)
        return this.select.cursorNextMatch(re, wrap, n);
    const iface = this.iface;
    const cx = this.cursorx;
    const cy = this.cursory;
    if (iface == null)
        return;
    const [x, y, w] = await iface.findNextMatch(re, cx, cy, wrap, n);
    this.onMatch(x, y, w, refresh);
}

/* private */
Buffer.prototype.cursorPrevMatch = async function(re, wrap, refresh, n) {
    if (this.select)
        return this.select.cursorPrevMatch(re, wrap, n);
    const iface = this.iface;
    const cx = this.cursorx;
    const cy = this.cursory;
    if (iface == null)
        return;
    const [x, y, w] = await iface.findPrevMatch(re, cx, cy, wrap, n);
    this.onMatch(x, y, w, refresh);
}

/*
 * backwards compat
 * TODO remove once we have an official interface for these
 */
/* private */
Buffer.prototype.findPrevMatch = function(...args) {
    return this.iface.findPrevMatch(...args);
}

/* private */
Buffer.prototype.findNextMatch = function(...args) {
    return this.iface.findNextMatch(...args);
}

/*
 * RegExp literals are pre-compiled.
 * We skip compiling vi words for now because bytecode with Unicode gets
 * obscenely large.
 */
const ReWordStart = /(?<!\w)\w/gu;
/* kana, han, hangul, other alpha & non-alpha (symbol) */
const ReViWordStart = new RegExp(
    String.raw`((?<!\p{sc=Hira})\p{sc=Hira})|((?<!\p{sc=Kana})\p{sc=Kana})|((?<!\p{sc=Han})\p{sc=Han})|((?<!\p{sc=Hang})\p{sc=Hang})|((?<!\w)\w)|((?<![^\p{L}\p{Z}\p{N}])[^\p{L}\p{Z}\p{N}])`,
    "gu"
);
const ReBigWordStart = /(?<!\S)\S/gu;

const ReWordEnd = /\w(?!\w)/gu;
/* kana, han, hangul, other alpha & non-alpha (symbol) */
const ReViWordEnd = new RegExp(
    String.raw`(\p{sc=Hira}(?!\p{sc=Hira}))|(\p{sc=Kana}(?!\p{sc=Kana}))|(\p{sc=Han}(?!\p{sc=Han}))|(\p{sc=Hang}(?!\p{sc=Hang}))|(\w(?!\w))|([^\p{L}\p{Z}\p{N}](?![^\p{L}\p{Z}\p{N}]))`,
    "gu"
);
const ReBigWordEnd = /\S(?!\S)/gu;
const ReTextStart = /\S/gu;

/* private */
Buffer.prototype.cursorPrevWordImpl = async function(re, n = 1) {
    const cx = this.cursorx;
    const cy = this.cursory;
    const [x, y, w] = await this.findPrevMatch(re, cx, cy, false, n);
    if (y >= 0)
        this.setCursorXY(x + w - 1, y);
    else
        this.cursorLineBegin();
}

/* private */
Buffer.prototype.cursorNextWordImpl = async function(re, n = 1) {
    const cx = this.cursorx;
    const cy = this.cursory;
    const [x, y, w] = await this.findNextMatch(re, cx, cy, false, n);
    if (y >= 0 && x >= 0)
        this.setCursorXY(x + w - 1, y);
    else
        this.cursorLineEnd();
}

/* public */
Buffer.prototype.cursorPrevWord = function(n) {
    return this.cursorPrevWordImpl(ReWordEnd, n);
}

/* public */
Buffer.prototype.cursorPrevViWord = function(n) {
    return this.cursorPrevWordImpl(ReViWordEnd, n);
}

/* public */
Buffer.prototype.cursorPrevBigWord = function(n) {
    return this.cursorPrevWordImpl(ReBigWordEnd, n);
}

/* public */
Buffer.prototype.cursorNextWord = function(n) {
    return this.cursorNextWordImpl(ReWordStart, n);
}

/* public */
Buffer.prototype.cursorNextViWord = function(n) {
    return this.cursorNextWordImpl(ReViWordStart, n);
}

/* public */
Buffer.prototype.cursorNextBigWord = function(n) {
    return this.cursorNextWordImpl(ReBigWordStart, n);
}

/* public */
Buffer.prototype.cursorWordBegin = function(n) {
    return this.cursorPrevWordImpl(ReWordStart, n);
}

/* public */
Buffer.prototype.cursorViWordBegin = function(n) {
    return this.cursorPrevWordImpl(ReViWordStart, n);
}

/* public */
Buffer.prototype.cursorBigWordBegin = function(n) {
    return this.cursorPrevWordImpl(ReBigWordStart, n);
}

/* public */
Buffer.prototype.cursorWordEnd = function(n) {
    return this.cursorNextWordImpl(ReWordEnd, n);
}

/* public */
Buffer.prototype.cursorViWordEnd = function(n) {
    return this.cursorNextWordImpl(ReViWordEnd, n);
}

/* public */
Buffer.prototype.cursorBigWordEnd = function(n) {
    return this.cursorNextWordImpl(ReBigWordEnd, n);
}

/* public */
Buffer.prototype.getCurrentWord = async function(x = this.cursorx,
                                                 y = this.cursory) {
    const iface = this.iface
    if (iface == null)
        return;
    let p1 = iface.findPrevMatch(ReViWordStart, x + 1, y, false, 1);
    let p2 = iface.findNextMatch(ReViWordEnd, x - 1, y, false, 1);
    let [x1, y1, w1] = await p1;
    let [x2, y2, w2] = await p2;
    if (y1 < y)
        x1 = 0;
    if (y2 > y)
        x2 = 0;
    return iface.getSelectionText(x1, y, x2, y, "normal");
}

/* zb */
/* public */
Buffer.prototype.lowerPage = function(n) {
    if (n)
        this.setCursorY(n - 1);
    this.setFromY(this.cursory - this.height + 1);
}

/* z- */
/* public */
Buffer.prototype.lowerPageBegin = function(n) {
    this.lowerPage(n);
    this.cursorLineTextStart()
}

/* TODO centerLine */

/* z. */
/* public */
Buffer.prototype.centerLineBegin = function(n) {
    this.centerLine(n);
    this.cursorLineTextStart();
}

/* zt */
/* public */
Buffer.prototype.raisePage = function(n) {
    if (n)
        this.setCursorY(n - 1);
    this.setFromY(this.cursory);
}

/* z^M */
/* public */
Buffer.prototype.raisePageBegin = function(n) {
    this.raisePage(n);
    this.cursorLineTextStart();
}

/* z+ */
/* public */
Buffer.prototype.nextPageBegin = function(n) {
    this.setCursorY(n ? n - 1 : this.fromy + this.height);
    this.cursorLineTextStart();
    this.raisePage();
}

/* z^ */
/* public */
Buffer.prototype.previousPageBegin = function(n) {
    this.setCursorY(n ? n - this.height : this.fromy - 1); /* +-1 cancels out */
    this.cursorLineTextStart();
    this.lowerPage();
}

/* private */
Buffer.prototype.startSelection = function(t, mouse,
                                           x1 = this.cursorFirstX()) {
    const iface = this.iface;
    if (iface == null)
        return;
    const selection = iface.startSelection(t, mouse,
                                           x1, this.cursory,
                                           this.cursorx, this.cursory)
    this.currentSelection = selection;
    return selection;
}

/* private */
Buffer.prototype.clearSelection = function() {
    const iface = this.iface;
    if (iface == null)
        return;
    iface.removeHighlight(this.currentSelection);
    this.currentSelection = null;
}

/* public */
Buffer.prototype.cursorToggleSelection = function(n = 1, opts = {}) {
    if (this.currentSelection) {
        this.clearSelection();
        return null;
    }
    const cx = this.cursorFirstX();
    this.cursorRight(n - 1);
    return this.startSelection(opts.selectionType ?? "normal", false, cx);
}

/* public */
Buffer.prototype.cursorLineBegin = function() {
    this.setCursorX(-1);
}

/* public */
Buffer.prototype.cursorLineEnd = function() {
    this.setCursorX(Util.MAX_INT32);
}

/* public */
Buffer.prototype.cursorLineTextStart = function() {
    const iface = this.iface;
    if (iface == null)
        return;
    const [s, e] = iface.matchFirst(/\S/, this.cursory);
    if (s >= 0) {
        const x = this.currentLineWidth(0, s);
        this.setCursorX(x > 0 ? x : x - 1);
    } else
        this.cursorLineEnd();
}

/* public */
Buffer.prototype.cursorNextParagraph = async function(n = 1) {
    const iface = this.iface;
    if (iface == null)
        return;
    this.markPos0();
    const y = await iface.findNextParagraph(this.cursory, n);
    this.setCursorY(y)
    this.markPos();
}

/* public */
Buffer.prototype.cursorPrevParagraph = async function(n = 1) {
    return this.cursorNextParagraph(-n);
}

/* public */
Buffer.prototype.cursorNextLink = async function(n = 1) {
    const iface = this.iface;
    if (iface == null)
        return;
    this.markPos0();
    const [x, y] = await iface.findNextLink(this.cursorx, this.cursory, n);
    if (y >= 0) {
        this.setCursorXY(x, y);
        this.markPos();
    }
}

/* public */
Buffer.prototype.cursorPrevLink = async function(n = 1) {
    const iface = this.iface;
    if (iface == null)
        return;
    this.markPos0();
    const [x, y] = await iface.findPrevLink(this.cursorx, this.cursory, n);
    if (y >= 0) {
        this.setCursorXY(x, y);
        this.markPos();
    }
}

/* public */
Buffer.prototype.cursorNthLink = async function(n = 1) {
    const iface = this.iface;
    if (iface == null)
        return;
    const pos = await iface.findNextLink(0, 0, n);
    if (y >= 0)
        this.setCursorXYCenter(...pos);
}

/* public */
Buffer.prototype.cursorRevNthLink = async function(n = 1) {
    const iface = this.iface;
    if (iface == null)
        return;
    const pos = await iface.findRevNthLink(n);
    if (y >= 0)
        this.setCursorXYCenter(...pos);
}

/* public */
Buffer.prototype.cursorLinkNavDown = async function(n = 1) {
    const iface = this.iface;
    if (iface == null)
        return;
    this.markPos0();
    const [x, y] = await iface.findNextLink(this.cursorx, this.cursory, n);
    if (y < 0) {
        if (this.numLines <= this.height) {
            const [x2, y2] = await iface.findNextLink(-1, 0, 1);
            this.setCursorXYCenter(x2, y2);
        } else
            this.pageDown();
        this.markPos();
    } else if (y < this.fromy + this.height) {
        this.setCursorXYCenter(x, y);
        this.markPos();
    } else {
        this.pageDown();
        if (y < this.fromy + this.height) {
            this.setCursorXYCenter(x, y);
            this.markPos()
        }
    }
}

/* public */
Buffer.prototype.cursorLinkNavUp = async function(n = 1) {
    const iface = this.iface;
    if (iface == null)
        return;
    const [x, y] = await iface.findPrevLink(this.cursorx, this.cursory, n);
    if (y < 0) {
        const numLines = this.numLines;
        if (numLines <= this.height) {
            const [x2, y2] = await iface.findPrevLink(Util.MAX_INT32,
                                                      numLines - 1, 1);
            this.setCursorXYCenter(x2, y2);
        } else
            this.pageUp();
        this.markPos();
    } else if (y >= this.fromy) {
        this.setCursorXYCenter(x, y);
        this.markPos();
    } else {
        this.pageUp();
        if (y >= this.fromy) {
            this.setCursorXYCenter(x, y);
            this.markPos();
        }
    }
}

/* public */
Buffer.prototype.cursorFirstLine = function() {
    this.markPos0();
    this.setCursorY(0);
    this.markPos();
}

/* public */
Buffer.prototype.cursorLastLine = function() {
    this.markPos0();
    this.setCursorY(this.numLines - 1);
    this.markPos();
}

/* public */
Buffer.prototype.gotoMark = function(id) {
    const pos = this.getMarkPos(id);
    if (pos == null)
        return false;
    this.markPos0();
    this.setCursorXYCenter(...pos);
    this.markPos();
    return true;
}

/* public */
Buffer.prototype.gotoMarkY = function(id) {
    const pos = this.getMarkPos(id);
    if (pos == null)
        return false;
    this.markPos0();
    this.setCursorXYCenter(0, pos[1]);
    this.markPos();
    return true;
}

/* public */
Buffer.prototype.setCursorYCenter = function(y) {
    const fy = this.fromy;
    this.setCursorY(y);
    if (fy != this.fromy)
        this.centerLine();
}

/* public */
Buffer.prototype.setCursorXCenter = function(x) {
    const fx = this.fromx;
    this.setCursorX(x);
    if (fx != fromx)
        this.centerColumn();
}

/* public */
Buffer.prototype.setAbsoluteCursorXY = function(x, y) {
    this.setCursorXY(this.fromx + x, this.fromy + y);
}

/* public */
Buffer.prototype.markURL = async function() {
    const iface = this.iface;
    if (iface == null)
        return;
    await iface.markURL();
    return this.sendCursorPosition();
}

/* public */
Buffer.prototype.reshape = function() {
    const iface = this.iface;
    if (iface == null)
        return;
    return iface.forceReshape();
}

/* public */
Buffer.prototype.editSource = function() {
    const url = pager.url;
    const path = url.protocol == "file:" ?
        decodeURIComponent(url.pathname) :
        pager.cacheFile;
    const cmd = pager.getEditorCommand(path)
    pager.extern(cmd);
}

/* public */
Buffer.prototype.saveSource = function() {
    pager.gotoURL("cache:" + this.cacheId, {save: true, url: this.url});
}

/* private */
Buffer.prototype.onclick = async function(res, save = false) {
    if (res == null)
        return;
    const iface = this.iface;
    switch (res.t) {
    case "open": {
        const request = res.open;
        const contentType = res.contentType;
        const url = new URL(request.url);
        const bufferProtocol = this.url.protocol;
        const urlProtocol = url.protocol;
        const sameProtocol = bufferProtocol == urlProtocol;
        if (request.method != "GET" && !sameProtocol &&
            !(Util.HttpLike.includes(bufferProtocol) &&
              Util.HttpLike.includes(urlProtocol))) {
            pager.alert("Blocked cross-protocol POST: " + url);
            return;
        }
        /* TODO this is horrible UX, async actions shouldn't block input */
        const hover = URL.parse(this.hoverLink);
        if (pager.buffer != this ||
            !save && (hover == null || !Util.isSameAuthOrigin(hover, url))) {
            const x = await pager.ask("Open pop-up? " + url);
            if (x && (!save || !pager.gotoURLHash(request, this)))
                pager.gotoURL(request, {contentType, save, referrer: this});
        } else if (save || !pager.gotoURLHash(request, this))
            pager.gotoURL(request, {contentType, save, referrer: this});
        break;
    } case "select": {
        const selected = await new Promise(resolve => {
            const selected = res.selected;
            this.select = new Select(res.options, selected,
                                     Math.max(this.acursorx - 1, 0),
                                     Math.max(this.acursory - 1 - selected, 0),
                                     this.width, this.height, resolve);
        });
        this.closeSelect();
        const res2 = await iface.select(selected);
        return this.onclick(res2);
    } case "read-password": case "read-text": {
        const text = await pager.setLineEdit("buffer", res.prompt, {
            current: res.value,
            hide: res.t == "read-password"
        });
        if (text == null)
            return iface.readCanceled();
        const res2 = await iface.readSuccess(text, -1);
        if (res2 != null)
            return this.onclick(res2);
        break;
    } case "read-area": {
        const text = await pager.openEditor(res.value);
        if (text == null)
            return iface.readCanceled();
        return iface.readSuccess(text, -1);
    } case "read-file": {
        const text = await pager.setLineEdit("download", "(Upload)Filename: ");
        if (text == null)
            return iface.readCanceled();
        const path = Util.unquote(text, Util.getcwd());
        if (path == null) {
            pager.alert("Invalid path: " + path);
            return iface.readCanceled();
        }
        const fd = Util.openFile(path);
        if (fd < 0) {
            pager.alert("File not found");
            return iface.readCanceled();
        }
        if (!Util.isFile(fd)) {
            Util.closeFile(fd);
            pager.alert("Not a file: " + path);
            return iface.readCanceled();
        }
        const name = path.substring(path.lastIndexOf('/') + 1);
        const res2 = await iface.readSuccess(name, fd);
        if (res2 != null)
            return this.onclick(res2);
    }}
}

/* public */
Buffer.prototype.click = async function(n = 1) {
    this.showLoading();
    const iface = this.iface;
    if (iface == null)
        return;
    const res = await iface.click(this.cursorx, this.cursory, n);
    return this.onclick(res);
}

/* private */
Buffer.prototype.submitForm = async function() {
    const iface = this.iface;
    if (iface == null)
        return;
    const res = await iface.submitForm(this.cursorx, this.cursory);
    return this.onclick(res);
}

/* public */
Buffer.prototype.saveLink = async function() {
    const iface = this.iface;
    if (iface == null)
        return;
    const res = await iface.click(this.cursorx, this.cursory, 1);
    return this.onclick(res, true);
}

/* public */
Buffer.prototype.showLinkHints = async function() {
    const iface = this.iface;
    if (iface == null)
        return [];
    const sx = this.fromx;
    const sy = this.fromy;
    const ex = sx + this.width;
    const ey = sy + this.height;
    return iface.showHints(sx, sy, ex, ey);
}

/* private */
Buffer.prototype.hideLinkHints = function() {
    const iface = this.iface;
    if (iface == null)
        return;
    return iface.hideHints();
}

/* private */
Buffer.prototype.contextMenu = function() {
    const iface = this.iface;
    if (iface == null)
        return;
    return iface.contextMenu(this.cursorx, this.cursory);
}

/* public */
Buffer.prototype.getSelectionText = function(sel = this.currentSelection) {
    const iface = this.iface;
    if (iface == null || sel == null)
        return "";
    return iface.getSelectionText(sel.startx, sel.starty, sel.endx, sel.endy,
        sel.selectionType)
}

/* public */
Buffer.prototype.saveScreen = async function() {
    let path = await pager.setLineEdit("download", "Save buffer to: ");
    if (path == null)
        return;
    path = Util.unquote(path, Util.getcwd());
    const iface = this.iface;
    if (iface == null) {
        pager.alert("page is not loaded yet");
        return;
    }
    const text = await iface.getSelectionText(0, 0, 0, this.numLines, "line");
    try {
        writeFile(path, text);
    } catch (e) {
        pager.alert(e);
    }
}

/* public */
Buffer.prototype.editScreen = async function() {
    const iface = this.iface;
    if (iface == null) {
        pager.alert("page is not loaded yet");
        return;
    }
    const text = await iface.getSelectionText(0, 0, 0, this.numLines, "line");
    try {
        const tmp = pager.getTempFile();
        writeFile(tmp, text);
        const cmd = pager.getEditorCommand(tmp);
        if (cmd == "")
            throw new TypeError("invalid external.editor command");
        pager.extern(cmd);
    } catch (e) {
        pager.alert(e);
    }
}

/* private */
Buffer.prototype.loaded = async function(headless, metaRefresh, autofocus) {
    const replace = this.unsetReplace();
    if (replace != null)
        pager.deleteContainer(replace, this);
    pager.numload--;
    if (this == pager.buffer) {
        if (pager.alertState == "loadInfo")
            pager.alertState = "normal";
        pager.queueStatusUpdate();
    }
    if (!this.hasStart) {
        if (!headless)
            this.sendCursorPosition();
        const anchor = this.url.hash.substring(1);
        if (anchor != "" || autofocus) {
            const [x, y, click] = await this.iface.gotoAnchor(anchor, autofocus,
                                                              true);
            if (y >= 0) {
                this.setCursorXYCenter(x, y);
                const ReadLine = ["read-text", "read-password", "read-file"];
                if (click != null && ReadLine.includes(click.t))
                    await this.onclick(click);
            }
        }
    }
    if (metaRefresh != "never") {
        let url = this.refreshUrl;
        let n = this.refreshMillis;
        if (n == -1)
            [n, url] = await this.iface.checkRefresh();
        let ok = n >= 0;
        if (ok && metaRefresh != "always") {
            const surl = url + "";
            const refreshAllowed = pager.refreshAllowed;
            if (!refreshAllowed.has(surl)) {
                ok = await pager.ask(`Redirect to ${surl} (in ${n}ms?)`);
                if (ok)
                    refreshAllowed.add(surl);
            }
        }
        if (ok) {
            setTimeout(() => {
                if (replace.iface != null) {
                    pager.gotoURL(url, {replace, history: replace.history})
                        .copyCursorPos(replace);
                }
            }, n);
        }
    }
}
