/*
 * Script executed at startup.
 *
 * Note: since much of the public API is now implemented in JS, we mark
 * documented functions as "public" and undocumented functions as
 * "private".  This has nothing to do with the language-level visibility of
 * functions (but obviously #private can be assumed to be undocumented too.)
 */

globalThis.cmd = {
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
        const link = pager.buffer.hoverImage;
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
        if ((pager.commandMode = pager.pinned.console != pager.buffer)) {
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
        if (!pager.menu && pager.buffer != null) {
            const canceled = await pager.buffer.contextMenu();
            if (!canceled)
                return pager.openMenu()
        } else
            pager.closeMenu()
    },
    toggleMenu: () => pager.menu ? pager.closeMenu() : pager.openMenu(),
    viewImage: (_, save) => {
        let contentType = null;
        let url = null;
        if (pager.buffer.hoverCachedImage) {
            [url, contentType] = pager.buffer.hoverCachedImage.split(' ');
            url = 'file:' + pager.getCacheFile(url, pager.buffer.process);
        } else if (pager.buffer.hoverImage)
            url = new Request(pager.buffer.hoverImage, {headers: {Accept: "*/*"}});
        if (url)
            pager.gotoURL(url, {contentType: contentType, save: save});
    },
    toggleScripting: () => {
        const buffer = pager.buffer;
        const buffer2 = pager.gotoURL(buffer.url, {
            contentType: buffer.init.contentType,
            history: buffer.init.history,
            replace: buffer,
            scripting: !buffer.init.scripting,
            cookie: buffer.init.cookie
        });
        if (buffer2)
            buffer2.init.copyCursorPos(buffer.iface ?? buffer.init)
    },
    toggleCookie: () => {
        const buffer = pager.buffer;
        const buffer2 = pager.gotoURL(buffer.url, {
            contentType: buffer.init.contentType,
            history: buffer.init.history,
            replace: buffer,
            scripting: buffer.init.scripting,
            cookie: !buffer.init.cookie
        });
        if (buffer2)
            buffer2.init.copyCursorPos(buffer.iface ?? buffer.init)
    },
    /* vi G */
    gotoLineOrEnd: n => pager.gotoLine(n ?? pager.buffer.numLines),
    /* vim gg */
    gotoLineOrStart: n => pager.gotoLine(n ?? 1),
    /* vi | */
    gotoColumnOrBegin: n => pager.buffer.setCursorXCenter((n ?? 1) - 1),
    gotoColumnOrEnd: n =>
        n ? pager.buffer.setCursorXCenter(n - 1) : pager.buffer.cursorLineEnd(),
    selectOrCopy: n => {
        if (pager.currentSelection)
            cmd.buffer.copySelection();
        else
            pager.buffer.cursorToggleSelection(n)
    },
    cursorToggleSelectionLine:
        n => pager.buffer.cursorToggleSelection(n, {selectionType: "line"}),
    cursorToggleSelectionBlock:
        n => pager.buffer.cursorToggleSelection(n, {selectionType: "block"}),
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

/* public */
globalThis.quit = function() {
    pager.quit();
}

/* public */
globalThis.suspend = function() {
    pager.suspend();
}

/* private */
globalThis.feedNext = function() {
    pager.feedNext = true;
}

/* private */
globalThis.__defineGetter__("line", function() {
    return pager.lineEdit;
});

/* buffer, precnum */
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
        "cursorToggleSelection", "cursorNthLink", "cursorRevNthLink"]) {
    cmd[it] = n => pager[it](n);
}

/* pager, no precnum */
for (const it of ["redraw", "cancel", "toggleSource", "nextBuffer",
        "prevBuffer", "lineInfo", "discardBuffer", "discardBufferTree",
        "searchForward", "searchBackward", "isearchForward", "isearchBackward",
        "discardTree", "dupeBuffer", "load", "loadCursor", "saveLink",
        "toggleImages", "writeInputBuffer", "showFullAlert", "toggleLinkHints",
        "peek", "peekCursor", "quit", "suspend"]) {
    cmd[it] = () => pager[it]();
}

/* buffer, no precnum */
for (const it of ["markURL", "reshape", "cursorLineBegin",
        "cursorLineTextStart", "cursorLineEnd", "cursorMiddleColumn",
        "cursorLeftEdge", "cursorRightEdge", "cursorMiddle", "saveLink",
        "saveScreen", "saveSource", "editScreen", "editSource",
        "toggleImages"]) {
    cmd[it] = () => pager[it]();
}

/* line */
for (const it of ["submit", "backspace", "delete", "cancel", "prevWord",
        "nextWord", "backward", "forward", "clear", "kill", "clearWord",
        "killWord", "begin", "end", "escape", "prevHist", "nextHist"]) {
    cmd.line[it] = () => pager.lineEdit[it]();
}

/* backwards compat: cmd.pager and cmd.buffer used to be separate */
cmd.pager = cmd.buffer = cmd;

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
    const fun = x => url + encodeURIComponent(x.substring(x.indexOf(':') + 1));
    config.addOmniRule(name, match, fun);
}

/* private */
Pager.prototype.init = function(pages, contentType, charset, history, pipe) {
    globalThis.pager = this;
    try {
        config.initCommands();
    } catch (e) {
        pager.alert(e + '\n' + e.stack);
        quit(1);
    }
    this.pinned = {
        downloads: null,
        console: null,
        prev: null,
    };
    this.navDirection = "prev"; /* "prev", "next", "any" */
    this.mouse = new Mouse();
    this.tab = this.tabHead = new Tab();
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
            contentType: contentType || "text/x-ansi"
        });
    }
    const init = {contentType, charset, history};
    for (const page of pages)
        this.loadSubmit(page, init);
    this.showAlerts();
    if (!config.start.headless)
        this.inputLoop();
    else {
        this.headlessLoop();
        let tab = this.tabHead;
        loop:
        while (tab != null) {
            let buffer = tab.head;
            while (buffer != null) {
                if (!this.drawBuffer(buffer.iface)) {
                    console.error("Error in buffer", buffer.url);
                    this.handleStderr(); /* dump errors */
                    break loop;
                }
                buffer = buffer.next
            }
            tab = tab.next;
        }
    }
}

/* public */
console.hide = function() {
    const pager = globalThis.pager;
    if (pager.consoleCacheId != -1 && pager.buffer == pager.pinned.console)
        pager.setBuffer(pager.pinned.prev);
}

/* public */
console.show = () => pager.showConsole();

const ConsoleTitle = "Browser Console";

/* public */
console.clear = function() {
    const pager = pager;
    if (pager.consoleCacheId == -1)
        return;
    if (!pager.addConsole())
        return;
    if (pager.pinned.console != null) {
        const request = new Request("cache:" + pager.consoleCacheId);
        const buffer = pager.gotoURL(request, {
            title: ConsoleTitle,
            history: false,
            replace: pager.pinned.console
        });
        if (buffer != null) {
            pager.pinned.console = buffer;
            pager.addTab(buffer);
        }
    }
}

/* private */
Pager.prototype.showConsole = function() {
    const cacheId = this.consoleCacheId;
    if (cacheId == -1)
        return;
    const current = this.buffer;
    if (this.pinned.console == null) {
        const request = new Request("cache:" + cacheId);
        const buffer = this.gotoURL(request, {
            title: ConsoleTitle,
            history: false,
            suppressAdd: true
        });
        if (buffer == null)
            return;
        this.pinned.console = buffer;
        this.addTab(buffer);
        this.consoleInit = buffer.init;
    }
    if (current != this.pinned.console) {
        this.pinned.prev = current;
        this.setBuffer(this.pinned.console);
    }
}

/* private */
Pager.prototype.setBuffer = function(buffer) {
    if (this.buffer?.iface != null)
        this.clearCachedImages(this.buffer.iface);
    if (buffer != null) {
        if (buffer.tab != this.tab)
            this.tab = buffer.tab;
        this.tab.current = buffer;
        this.bufferInit = buffer.init;
        this.copyLoadInfo(buffer.init);
        /* if iface is null, it will be set once the buffer is loaded */
        if (buffer.iface != null) {
            this.setVisibleBuffer(buffer);
        }
    } else {
        this.tab.current = null;
        this.bufferInit = null;
    }
}

/* private */
Pager.prototype.setVisibleBuffer = function(buffer) {
    this.updateTitle(buffer.init);
    this.bufferIface = buffer.iface;
    this.menu = buffer.select;
    buffer.iface.queueDraw();
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

/* private */
Pager.prototype.setLineEdit = async function(mode, prompt, obj) {
    if (this.lineEdit != null)
        this.lineEdit.cancel();
    const res = await this.setLineEdit0(mode, prompt, obj);
    this.unsetLineEdit();
    this.queueStatusUpdate();
    return res;
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
    } else if (buffer != null) {
        const cx = buffer.cursorx;
        const cy = buffer.cursory;
        const fx = buffer.fromx;
        const fy = buffer.fromy;
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
                const re = this.iregex;
                if (re instanceof RegExp) {
                    buffer.highlight = true; /* TODO private variable */
                    let wrap = config.search.wrap;
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
            this.setFromXY(fx, fy);
            this.setCursorXY(cx, cy);
        } else {
            delete this.isearchIter;
            if (text == "" && !this.regex) {
                this.setFromXY(fx, fy);
                this.setCursorXY(cx, cy);
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
                await buffer.iface.sendCursorPosition()
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

/* private */
Pager.prototype.setTab = function(buffer, tab) {
    const removed = buffer.setTab(tab);
    if (removed != null) {
        if (removed.next != null)
            removed.next.prev = removed.prev;
        if (removed.prev != null)
            removed.prev.next = removed.next;
        if (this.tabHead == removed)
            this.tabHead = removed.next;
        removed.prev = removed.next = null;
        /* tab cannot be null */
        if (this.tabHead == null)
            this.tab = this.tabHead = new Tab()
    }
}

/* private */
Pager.prototype.addBuffer = function(buffer) {
    this.navDirection = "next";
    this.setTab(buffer, this.tab);
    this.setBuffer(buffer);
}

/* public */
Pager.prototype.addTab = function(buffer = "about:blank") {
    if (!(buffer instanceof Buffer)) {
        let url = buffer instanceof URL ? buffer : new URL(buffer);
        buffer = this.gotoURL(url, {history: false});
        if (buffer == null)
            throw new TypeError("failed to go to " + url)
    }
    let tab = new Tab();
    const oldTab = this.tab;
    if (oldTab.next != null)
        oldTab.next.prev = tab;
    /* add to link first, or setTab dies */
    tab.prev = oldTab;
    tab.next = oldTab.next;
    if (tab.next != null)
        tab.next.prev = tab;
    oldTab.next = tab;
    pager.setTab(buffer, tab);
    this.setBuffer(buffer);
}

/* public */
Pager.prototype.prevTab = function() {
    if (this.tab.prev != null) {
        this.tab = this.tab.prev;
        this.setBuffer(this.buffer);
    } else
        pager.alert("No previous tab");
}

/* public */
Pager.prototype.nextTab = function() {
    if (this.tab.next != null) {
        this.tab = this.tab.next;
        this.setBuffer(this.buffer);
    } else
        pager.alert("No next tab");
}

/* public */
Pager.prototype.discardTab = function() {
    const tab = this.tab;
    const prevTab = tab.prev;
    const nextTab = tab.next;
    if (prevTab != null || nextTab != null) {
        let buffer = tab.head;
        while (buffer != null) {
            const next = buffer.next;
            this.deleteBuffer(buffer);
            buffer = next;
        }
        if (prevTab != null) {
            if (nextTab != null)
                nextTab.prev = prevTab;
            this.tab = prevTab;
        } else {
            nextTab.prev = prevTab;
            if (tab == this.tabHead)
                this.tabHead = nextTab;
            this.tab = nextTab;
        }
        this.setBuffer(this.buffer);
    } else
        this.alert("This is the last tab")
}

/* public */
Pager.prototype.gotoURL = function(request, obj) {
    const init = this.gotoURLImpl(request, obj);
    if (init == null)
        return null;
    const buffer = new Buffer(init, this.tab);
    buffer.retry = obj?.retry;
    const old = obj?.replace;
    if (old != null) {
        this.replaceWith(old, buffer);
        let replace = old;
        if (old.replace != null) {
            /* handle replacement chains by dropping everything in the
             * middle */
            replace = old.replace;
            this.deleteBuffer(old);
        }
        buffer.replace = replace;
        replace.replaceRef = buffer;
    } else if (!obj?.suppressAdd)
        this.addBuffer(buffer);
    return buffer;
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
    url.hash = anchor;
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
    return this.load(this.buffer.hoverLink || this.buffer.hoverImage);
}

/* Reload the page in a new buffer, then kill the previous buffer. */
/* public */
Pager.prototype.reload = function() {
    const old = this.buffer;
    if (!old)
        return;
    const buffer = this.gotoURL(old.url, {
        contentType: old.init.contentType,
        replace: old,
        history: old.init.history,
        charset: old.init.charsetOverride
    })
    buffer.init.copyCursorPos(old.iface ?? old.init);
}

/* public */
Pager.prototype.externFilterSource = function(cmd, buffer = this.buffer,
                                              contentType = null) {
    contentType ??= buffer.init.contentType || "text/plain";
    const init = this.initBufferFrom(buffer.init, contentType, cmd);
    if (init != null) {
        const buffer = new Buffer(init, this.tab);
        this.addBuffer(buffer);
    }
}

/* public */
Pager.prototype.toggleSource = function() {
    const buffer = this.buffer;
    if (buffer == null)
        return;
    if (buffer.sourcePair != null)
        this.setBuffer(buffer.sourcePair);
    else {
        const ishtml = buffer.init.ishtml;
        /* TODO I wish I could set the contentType to whatever I wanted,
         * not just HTML */
        const contentType = ishtml ? "text/plain" : "text/html";
        const init = pager.initBufferFrom(buffer.init, contentType, "");
        if (init != null) {
            const buffer2 = new Buffer(init, this.tab);
            buffer2.sourcePair = buffer;
            buffer.sourcePair = buffer2;
            this.addBuffer(buffer2);
        }
    }
}

/* public */
Pager.prototype.discardTree = function(buffer = this.buffer) {
    while (buffer != null) {
        const next = buffer.next;
        this.deleteBuffer(buffer);
        buffer = next;
    }
}

/* public */
Pager.prototype.dupeBuffer = function() {
    this.dupeBuffer2(this.buffer, this.buffer.url)
}

/* private */
Pager.prototype.dupeBuffer2 = function(buffer, url) {
    const init2 = new BufferInit(url, buffer.init);
    const iface = this.clone(buffer.iface, init2, url);
    if (iface == null) {
        this.alert("Failed to duplicate buffer.");
        return;
    }
    const buffer2 = new Buffer(init2, this.tab);
    buffer2.iface = iface;
    buffer2.currentSelection = buffer.currentSelection;
    this.addBuffer(buffer2);
    return buffer2;
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
    this.setBuffer(next);
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
            console.log(e + '\n' + e.stack.trimEnd());
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
    if (target == buffer)
        buffer.markPos0();
    target.setCursorY(n);
    if (target == buffer)
        buffer.markPos();
}

/* public */
Pager.prototype.peek = function() {
    const buffer = this.buffer;
    if (buffer != null)
        this.alert(buffer.url);
}

/* public */
Pager.prototype.ask = async function(prompt) {
    const s = await this.askChar(this.fitAskPrompt(prompt));
    switch (s) {
    case "y": return true;
    case "n": return false;
    default: return this.ask(prompt);
    }
}

/* private */
Pager.prototype.toggleLinkHints = async function() {
    const buffer = this.buffer;
    buffer.markPos0();
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
        buffer.markPos();
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
    const w = iface.currentLineWidth();
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
    this.menu = null;
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

/* public */
Pager.oppositeDir = function(dir) {
    switch (dir) {
    case "prev": return "next";
    case "next": return "prev";
    case "any": return "any";
    default: throw new TypeError("direction expected");
    }
};

/* public */
Pager.prototype.__defineGetter__("buffer", function() {
    return this.tab.current;
});

/* public */
Pager.prototype.__defineGetter__("revDirection", function() {
    return Pager.oppositeDir(this.navDirection);
});

/* public */
Pager.prototype.__defineGetter__("cacheFile", function() {
    const buffer = this.buffer;
    if (buffer == null)
        return "";
    return this.getCacheFile(buffer.cacheId);
});

/* public */
Pager.prototype.discardBuffer = function(buffer = this.buffer, dir = null) {
    if (dir != null)
        this.navDirection = Pager.oppositeDir(dir);
    dir = this.revDirection;
    const setTarget = buffer.find(dir);
    if (buffer == null || setTarget == null)
        this.alert(dir == "next" ? "No next buffer" : "No previous buffer");
    else
        this.deleteBuffer(buffer, setTarget);
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
                return this.evalInputAction(map, 0);
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
            }
        }
        break;
    case "mouse":
        return this.handleMouseInput(mouseInput);
    case "windowChange":
        let tab = this.tabHead;
        const width = this.bufWidth;
        const height = this.bufHeight;
        while (tab != null) {
            let buffer = tab.head;
            while (buffer != null) {
                buffer.init.width = width;
                buffer.init.height = height;
                const iface = buffer.iface;
                if (iface != null) {
                    (function(buffer) {
                        iface.windowChange(buffer.cursorx, buffer.cursory)
                            .then(pos => buffer.setCursorXYCenter(...pos));
                    })(buffer);
                }
                const select = buffer.select;
                if (select != null)
                    select.windowChange(width, height);
                buffer = buffer.next;
            }
            tab = tab.next;
        }
        break;
    }
}

/* private */
Pager.prototype.replaceWith = function(old, replacement) {
    if (replacement.prev != null)
        replacement.prev.next = replacement.next;
    if (replacement.next != null)
        replacement.next.prev = replacement.prev;
    if (old.tab.head == old)
        old.tab.head = replacement;
    replacement.prev = old.prev;
    replacement.next = old.next;
    replacement.tab = old.tab;
    old.prev = old.next = old.tab = null;
    if (replacement.prev != null)
        replacement.prev.next = replacement
    if (replacement.next != null)
        replacement.next.prev = replacement
    for (const name in this.pinned) {
        if (this.pinned[name] == old)
            this.pinned[name] = replacement;
    }
    if (this.buffer == old)
        this.setBuffer(replacement);
}

/* private */
Pager.prototype.deleteBuffer = function(buffer, setTarget = null) {
    const iface = buffer.iface;
    if (iface != null && iface.loadState == "loading")
        iface.cancel();
    if (buffer.sourcePair != null)
        buffer.sourcePair = buffer.sourcePair.sourcePair = null;
    if (buffer.replaceRef != null)
        buffer.replaceRef = buffer.replaceRef.replace = null;
    if (buffer.replace != null)
        buffer.replace = buffer.replace.replaceRef = null;
    const wasCurrent = this.buffer == buffer;
    this.setTab(buffer, null);
    for (const name in this.pinned) {
        if (this.pinned[name] == buffer)
            this.pinned[name] = null;
    }
    if (wasCurrent) {
        if (iface != null)
            this.clearCachedImages(iface);
        this.setBuffer(setTarget);
    }
    if (iface != null)
        this.unregisterBufferIface(iface);
    else
        this.unregisterBufferInit(buffer.init);
}

/* private */ class Tab {
    head = null; /* Buffer */
    current = null; /* Buffer */
    prev = null; /* Tab */
    next = null; /* Tab */
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

/* public */ class Buffer {
    /* public Highlight */ currentSelection = null;
    /* public Select */ select = null;
    /* public Buffer */ prev = null;
    /* public Buffer */ next = null;

    /* private Buffer */ sourcePair = null;
    /* private Buffer */ replace = null;
    /* private Buffer */ replaceRef = null;
    /* private URL */ retry = null;
    /* private BufferInterface */ iface = null;
    /* private BufferInit */ init;
    /* private Tab */ tab;

    /* private */ constructor(init, tab) {
        if (!(init instanceof BufferInit) || !(tab instanceof Tab))
            throw new TypeError("invalid arguments");
        this.init = init;
        this.tab = tab;
        init.connected = this.#connected.bind(this);
    }

    /* private */ get acursorx() {
        return this.iface?.acursorx ?? 0;
    }

    /* private */ get acursory() {
        return this.iface?.acursory ?? 0;
    }

    /* private */ async #connected(res, arg0) {
        const pager = globalThis.pager;
        switch (res) {
        case "connected": {
            this.iface = arg0;
            return this.#startLoad();
        } case "redirect": {
            const request = arg0;
            const redirectDepth = this.init.redirectDepth;
            if (redirectDepth < config.network.maxRedirect) {
                const url = new URL(request.url);
                const requestProto = url.protocol;
                const bufferProto = this.url.protocol;
                if (bufferProto != requestProto && bufferProto != "cgi-bin:") {
                    if (requestProto == "cgi-bin:") {
                        pager.alert("Blocked redirection attempt to " + url);
                        return;
                    }
                    if (!(Util.HttpLike.includes(bufferProto) &&
                          Util.HttpLike.includes(requestProto))) {
                        const x =
                            await pager.ask("Warning: switch protocols? " +
                                            url);
                        if (!x)
                            return;
                    }
                }
                pager.numload--;
                const save = this.init.save;
                if (save || !pager.gotoURLHash(request, this)) {
                    const nc = pager.gotoURL(request, {
                        history: this.init.history,
                        save: save,
                        redirectDepth: redirectDepth + 1,
                        referrer: this.init
                    });
                    if (nc != null) {
                        const replace = this.#popReplace();
                        pager.replaceWith(this, nc);
                        if (replace != null) {
                            nc.replace = replace;
                            replace.replaceRef = nc;
                        }
                        nc.setLoadInfo("Redirecting to " + url);
                    }
                }
            } else {
                pager.alert("Error: maximum redirection depth reached")
                pager.deleteBuffer(this, buffer.find("any"))
            }
            break;
        } case "unauthorized": {
            const url = new URL(this.url)
            const username = await pager.setLineEdit("username", "Username: ", {
                current: url.username
            });
            if (username == null) {
                pager.discardBuffer(this);
                return;
            }
            const password = await pager.setLineEdit("password", "Password: ", {
                hide: true
            });
            if (password != null) {
                url.username = username;
                url.password = password;
                const buffer2 = pager.gotoURL(url, {referrer: this.init});
                pager.replaceWith(this, buffer2);
            } else
                pager.discardBuffer(this);
            break;
        } case "fail": {
            if (this.replace != null) /* deleteBuffer unsets replace etc. */
                pager.replaceWith(this, this.replace);
            pager.deleteBuffer(this, this.find("any"));
            const retry = this.retry;
            if (retry != null) {
                pager.gotoURL(retry, {
                    contentType: this.init.contentType,
                    history: this.init.history
                });
            } else {
                /*
                 * Add to the history anyway, so that the user can edit the URL.
                 */
                if (this.init.history)
                    pager.addHist("location", this.init.url);
                /*
                 * Try to fit a meaningful part of the URL and the error
                 * message too.
                 * URLs can't include double-width chars, so we can just use
                 * string length for those.  (However, error messages can.)
                 */
                let msg = "Can't load " + this.init.url;
                const ew = Util.width(arg0);
                const width = pager.statusWidth;
                if (msg.length + ew > width) {
                    msg = msg.substring(0, Math.max(width - ew, width / 3) + 1);
                    if (msg.length > 0)
                        msg += '$';
                }
                pager.alert(`${msg} (${arg0})`);
            }
            break;
        } case "cancel": {
            pager.deleteBuffer(this, this.find("any"));
            pager.queueStatusUpdate();
            break;
        } case "save": {
            let buf = config.external.downloadDir;
            if (buf[0] != '/')
                buf += '/';
            const path = this.init.url.pathname;
            if (path.at(-1) == '/')
                buf += "index.html";
            else
                buf += decodeURI(path.substring(path.lastIndexOf('/') + 1));
            pager.deleteBuffer(this, this.find("any"));
            pager.queueStatusUpdate();
            for (;;) {
                const text = await pager.setLineEdit("download",
                                                     "(Download)Save file to: ",
                {
                    current: buf,
                    hide: false
                });
                if (text == null)
                    return this.init.closeMailcap();
                const path = Util.unquote(text, Util.getcwd());
                if (path != null && pager.saveTo(this.init, path))
                    break;
                const x = await pager.ask(`Cannot save to ${path}.  Retry?`);
                if (!x)
                    return this.init.closeMailcap();
                continue;
            }
            if (config.external.showDownloadPanel) {
                const old = pager.pinned.downloads;
                const downloads = pager.gotoURL("about:downloads", {
                    history: false,
                    replace: old
                });
                if (downloads != null && old != null)
                    pager.setBuffer(downloads);
                pager.pinned.downloads = downloads;
            }
            break;
        } case "mailcap": {
            const init = this.init;
            /* we must reset connectedPtr for connected2 */
            init.connected = this.#connected.bind(this);
            let i = arg0;
            let sx = 0;
            loop:
            for (;;) {
                const [prev, next] = pager.findMailcapPrevNext(init, i);
                const s = await pager.askMailcap(init, i, sx, prev, next);
                let mailcapFlag;
                switch (s) {
                case '\x03', 'q':
                    pager.alert("Canceled");
                    init.closeMailcap();
                    break loop;
                case 'e':
                    /* TODO no idea how to implement save :/
                     * probably it should run use a custom reader that runs
                     * through auto.mailcap clearing any other entry. but maybe
                     * it's better to add a full blown editor like w3m has at
                     * that point... */
                    const text = await pager.setLineEdit("mailcap",
                                                         "Mailcap: ", {
                        current: init.shortContentType + ';'
                    });
                    if (text == null)
                        break;
                    try {
                        pager.applyMailcap(init, text);
                    } catch (e) {
                        break;
                    }
                    break loop;
                case 's': case 'S':
                    init.save = true;
                    if (s == 'S')
                        pager.addMailcapEntry(init, "exec cat", "x-saveoutput");
                    break loop;
                case 't': case 'T':
                    if (s == 'T')
                        pager.addMailcapEntry(init, "exec cat", "copiousoutput");
                    break loop;
                case 'r': case 'R':
                    if (i < 0)
                        break;
                    if (s == 'R')
                        pager.saveMailcapEntry(i);
                    pager.applyMailcap(init, i);
                    break loop;
                /* navigation */
                case 'p': case 'k':
                    if (prev != -1)
                        i = prev;
                    break;
                case 'n': case 'j':
                    if (next != -1)
                        i = next;
                    break;
                case 'h': sx = Math.max(sx - 1, 0); break;
                case 'l': sx = Math.max(sx + 1, 0); break;
                case '^': case '\x01': sx = 0; break;
                case '$': case '\x05': sx = Number.MAX_SAFE_INTEGER; break;
                }
            }
            return pager.connected2(init);
        }}
    }

    async #startLoad() {
        let repaintLoopPromise, titlePromise;
        if (!this.init.headless) {
            repaintLoopPromise = (async () => {
                for (;;) {
                    if (this.numLines > 0 && pager.bufferInit == this.init &&
                        pager.bufferIface != this.iface) {
                        pager.setVisibleBuffer(this);
                    }
                    await this.iface.onReshape();
                    await this.iface.requestLines(true);
                }
            })();
        }
        titlePromise = this.iface.getTitle().then(title => {
            if (title != "") {
                this.init.title = title;
                if (pager.buffer == this) {
                    if (this.iface != null && this.iface.loadState != "loading")
                        pager.queueStatusUpdate();
                    pager.updateTitle(this.init);
                }
            }
        });
        loop:
        while (this.iface.loadState != "canceled") {
            const [n, len, bs] = await this.iface.load();
            switch (bs) {
            case "loadingPage":
                this.setLoadInfo(`${Util.convertSize(n)} loaded`);
                break;
            case "loadingResources":
                this.setLoadInfo(`${n}/${len} stylesheets loaded`);
                break;
            case "loadingImages":
                this.setLoadInfo(`${n}/${len} images loaded`);
                break;
            default: /* loaded */
                if (!this.iface.gotLines)
                    await this.iface.requestLines();
                break loop;
            }
        }
        this.setLoadInfo("");
        this.iface.loadState = "loaded";
        if (pager.bufferInit == this.init && pager.bufferIface != this.iface)
            pager.setVisibleBuffer(this);
        const replace = this.#popReplace();
        if (replace != null)
            pager.deleteBuffer(replace, this);
        pager.numload--;
        if (this == pager.buffer) {
            if (pager.alertState == "loadInfo")
                pager.alertState = "normal";
            pager.queueStatusUpdate();
        }
        if (!this.init.hasStart) {
            if (!this.init.headless)
                this.iface.sendCursorPosition();
            const anchor = this.url.hash.substring(1);
            const autofocus = this.init.autofocus;
            if (anchor != "" || autofocus) {
                const [x, y, click] = await this.iface.gotoAnchor(anchor,
                                                                  autofocus,
                                                                  true);
                if (y >= 0) {
                    this.setCursorXYCenter(x, y);
                    const ReadLine = ["read-text", "read-password", "read-file"];
                    if (click != null && ReadLine.includes(click.t))
                        await this.#onclick(click);
                }
            }
        }
        const metaRefresh = this.init.metaRefresh;
        if (metaRefresh != "never") {
            let [n, url] = await this.iface.checkRefresh();
            url ??= this.url; /* null => reload (if n >= 0) */
            if (n >= 0 && metaRefresh != "always") {
                const surl = url + "";
                const refreshAllowed = pager.refreshAllowed;
                if (!refreshAllowed.has(surl)) {
                    const ok = await pager.ask(`Redirect to ${surl} (in ${n}ms?)`);
                    if (ok)
                        refreshAllowed.add(surl);
                    else
                        n = -1;
                }
            }
            if (n >= 0) {
                setTimeout(() => {
                    if (this.iface != null) {
                        pager.gotoURL(url, {
                            replace: this,
                            history: this.init.history
                        }).init.copyCursorPos(this.iface ?? this.init);
                    }
                }, n);
            }
        }
        await titlePromise;
        await repaintLoopPromise;
    }

    #popReplace() {
        const replace = this.replace;
        if (replace != null)
            replace.replaceRef = this.replace = null;
        return replace;
    }

    #append(other) {
        if (other.prev != null)
            other.prev.next = other.next;
        if (other.next != null)
            other.next.prev = other.prev;
        other.next = this.next;
        if (this.next != null)
            this.next.prev = other;
        other.prev = this;
        this.next = other;
    }

    #remove() {
        if (this.prev != null)
            this.prev.next = this.next;
        if (this.next != null)
            this.next.prev = this.prev;
        if (this.tab.current == this)
            this.tab.current = this.prev ?? this.next;
        if (this.tab.head == this)
            this.tab.head = this.next;
        this.tab = this.next = this.prev = null;
    }

    async #onclick(res, save = false) {
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
            let open = false;
            if (pager.buffer != this ||
                !save && (hover == null ||
                          !Util.isSameAuthOrigin(hover, url))) {
                const x = await pager.ask("Open pop-up? " + url);
                open = x && (!save || !pager.gotoURLHash(request, this));
            } else
                open = save || !pager.gotoURLHash(request, this);
            if (open) {
                pager.gotoURL(request, {
                    contentType,
                    save,
                    referrer: this.init
                });
            }
            break;
        } case "select": {
            const selected = await new Promise(resolve => {
                const selected = res.selected;
                this.select = new Select(res.options, selected,
                                         Math.max(this.acursorx - 1, 0),
                                         Math.max(this.acursory - 1 - selected, 0),
                                         this.width, this.height, resolve);
                pager.menu = this.select;
            });
            if (pager.menu == this.select)
                pager.menu = null;
            this.select = null;
            iface.queueDraw();
            const res2 = await iface.select(selected);
            return this.#onclick(res2);
        } case "read-password": case "read-text": {
            const text = await pager.setLineEdit("buffer", res.prompt, {
                current: res.value,
                hide: res.t == "read-password"
            });
            if (text == null)
                return iface.readCanceled();
            const res2 = await iface.readSuccess(text, -1);
            if (res2 != null)
                return this.#onclick(res2);
            break;
        } case "read-area": {
            const text = await pager.openEditor(res.value);
            if (text == null)
                return iface.readCanceled();
            return iface.readSuccess(text, -1);
        } case "read-file": {
            const text = await pager.setLineEdit("download",
                                                 "(Upload)Filename: ");
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
                return this.#onclick(res2);
        }}
    }

    /* private */ setTab(tab) {
        const oldTab = this.tab;
        if (oldTab != null)
            this.#remove();
        this.tab = tab;
        if (tab != null) {
            if (tab.current == null)
                tab.current = tab.head = this;
            else
                tab.current.#append(this);
        }
        if (oldTab != null && oldTab.current == null)
            return oldTab;
        return null;
    }

    /* private */ markPos0() {
        if (this.iface != null)
            this.iface.markPos0();
    }

    /* private */ markPos() {
        if (this.iface != null)
            this.iface.markPos();
    }

    /* private */ onMatch(x, y, w, refresh) {
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

    /* private */ async cursorNextMatch(re, wrap, refresh, n) {
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

    /* private */ async cursorPrevMatch(re, wrap, refresh, n) {
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

    /* private */ async #cursorPrevWordImpl(re, n = 1) {
        const cx = this.cursorx;
        const cy = this.cursory;
        const [x, y, w] = await this.findPrevMatch(re, cx, cy, false, n);
        if (y >= 0)
            this.setCursorXY(x + w - 1, y);
        else
            this.cursorLineBegin();
    }

    /* private */ async #cursorNextWordImpl(re, n = 1) {
        const cx = this.cursorx;
        const cy = this.cursory;
        const [x, y, w] = await this.findNextMatch(re, cx, cy, false, n);
        if (y >= 0 && x >= 0)
            this.setCursorXY(x + w - 1, y);
        else
            this.cursorLineEnd();
    }

    /*
     * backwards compat
     * TODO remove once we have an official interface for these
     */
    /* private */ findPrevMatch(...args) {
        return this.iface.findPrevMatch(...args);
    }

    /* private */ findNextMatch(...args) {
        return this.iface.findNextMatch(...args);
    }

    /* private */ startSelection(t, mouse, x1 = undefined) {
        const iface = this.iface;
        if (iface == null)
            return;
        x1 ??= iface.cursorFirstX;
        const selection = iface.startSelection(t, mouse, x1, this.cursory,
                                               this.cursorx, this.cursory)
        this.currentSelection = selection;
        return selection;
    }

    /* private */ clearSelection() {
        const iface = this.iface;
        if (iface == null)
            return;
        iface.removeHighlight(this.currentSelection);
        this.currentSelection = null;
    }

    /* private */ cancel() {
        const iface = this.iface;
        if (iface != null && iface.loadState != "loading")
            return;
        this.loadState = "canceled";
        this.setLoadInfo("");
        if (iface != null)
            iface.cancel();
        else {
            pager.numload--;
            pager.deleteBuffer(this, this.find("any"));
        }
        pager.alert("Canceled loading")
    }

    /* private */ setLoadInfo(msg) {
        this.init.loadInfo = msg;
        pager.copyLoadInfo(this.init);
    }

    /* private */ async submitForm() {
        const iface = this.iface;
        if (iface == null)
            return;
        const res = await iface.submitForm(this.cursorx, this.cursory);
        return this.#onclick(res);
    }

    /* public */ get numLines() {
        return this.iface?.numLines ?? 0;
    }

    /* public */ get url() {
        return this.init.url;
    }

    /* public */ get cacheId() {
        return this.init.cacheId;
    }

    /* public */ get width() {
        return this.init.width;
    }

    /* public */ get height() {
        return this.init.height;
    }

    /* public */ get title() {
        return this.init.title;
    }

    /* public */ get process() {
        return this.iface?.process ?? -1;
    }

    /* public */ get cursorx() {
        return this.iface?.cursorx ?? 0;
    }

    /* public */ get cursory() {
        return this.iface?.cursory ?? 0;
    }

    /* public */ get fromx() {
        return this.iface?.fromx ?? 0;
    }

    /* public */ get fromy() {
        return this.iface?.fromy ?? 0;
    }

    /* public */ get hoverLink() {
        return this.iface?.hoverLink ?? "";
    }

    /* public */ get hoverTitle() {
        return this.iface?.hoverTitle ?? "";
    }

    /* public */ get hoverImage() {
        return this.iface?.hoverImage ?? "";
    }

    /* private */ get hoverCachedImage() {
        return this.iface?.hoverCachedImage ?? "";
    }

    /* public */ find(dir) {
        switch (dir) {
        case "prev": return this.prev;
        case "next": return this.next;
        case "any": return this.prev ?? this.next;
        default: throw new TypeError("unexpected direction");
        }
    }

    /* public */ setCursorX(x, refresh = true, save = true) {
        if (this.iface != null) {
            this.iface.setCursorX(x, refresh, save);
            if (this.currentSelection != null) {
                x = this.iface.cursorx;
                if (x != this.currentSelection.x2) {
                    this.currentSelection.x2 = x;
                    this.iface.queueDraw();
                }
            }
        }
    }

    /* public */ setCursorY(y, refresh = true) {
        if (this.iface != null) {
            const oy = this.iface.cursory;
            this.iface.setCursorY(y, refresh);
            if (oy != y) {
                pager.queueStatusUpdate();
                if (this.currentSelection != null &&
                    y != this.currentSelection.y2) {
                    this.currentSelection.y2 = y
                    this.iface.queueDraw();
                }
            }
        }
    }

    /* public */ setFromX(x, refresh = true) {
        if (this.iface != null)
            this.iface.setFromX(x, refresh);
    }

    /* public */ setFromY(y) {
        if (this.iface != null)
            this.iface.setFromY(y);
    }

    /* public */ cursorDown(n = 1) {
        this.setCursorY(this.cursory + n);
    }

    /* public */ cursorUp(n = 1) {
        this.setCursorY(this.cursory - n);
    }

    /* public */ cursorLeft(n = 1) {
        this.setCursorX((this.iface?.cursorFirstX ?? 0) - n);
    }

    /* public */ cursorRight(n = 1) {
        this.setCursorX((this.iface?.cursorLastX ?? 0) + n);
    }

    /* public */ scrollDown(n = 1) {
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

    /* public */ scrollUp(n = 1) {
        const y = Math.max(this.fromy - n, 0);
        if (y < this.fromy) {
            this.setFromY(y);
            const dy = this.cursory - this.fromy - this.height + 1;
            if (dy > 0)
                this.cursorUp(dy);
        } else
            this.cursorUp(n);
    }

    /* public */ scrollRight(n = 1) {
        const iface = this.iface;
        if (iface == null)
            return;
        const msw = iface.maxScreenWidth();
        const x = Math.min(this.fromx + this.width + n, msw) - this.width;
        if (x > this.fromx)
            this.setFromX(x);
    }

    /* public */ scrollLeft(n = 1) {
        const x = Math.max(this.fromx - n, 0);
        if (x < this.fromx)
            this.setFromX(x);
    }

    /* public */ pageDown(n = 1) {
        const iface = this.iface;
        if (iface == null)
            return;
        const delta = this.height * n;
        this.setFromY(this.fromy + delta);
        this.setCursorY(this.cursory + delta);
    }

    /* public */ pageUp(n = 1) {
        this.pageDown(-n);
    }

    /* public */ pageLeft(n = 1) {
        this.setFromX(this.fromx - this.width * n);
    }

    /* public */ pageRight(n = 1) {
        this.setFromX(this.fromx + this.width * n);
    }

    /* I am not cloning the vi behavior of e.g. 2^D setting paging size because
     * it is counter-intuitive and annoying. */
    /* public */ halfPageDown(n = 1) {
        const iface = this.iface;
        if (iface == null)
            return;
        const delta = (this.height + 1) / 2 * n;
        this.setFromY(this.fromy + delta);
        this.setCursorY(this.cursory + delta);
    }

    /* public */ halfPageUp(n = 1) {
        this.halfPageDown(-n);
    }

    /* public */ halfPageLeft(n = 1) {
        this.setFromX(this.fromx - (this.width + 1) / 2 * n);
    }

    /* public */ halfPageRight(n = 1) {
        this.setFromX(this.fromx + (this.width + 1) / 2 * n);
    }

    /* public */ cursorTop(n = 1) {
        this.markPos0();
        this.setCursorY(this.fromy + Util.clamp(n - 1, 0, this.height - 1));
        this.markPos();
    }

    /* public */ cursorMiddle() {
        this.markPos0();
        this.setCursorY(this.fromy + (this.height - 2) / 2);
        this.markPos();
    }

    /* public */ cursorBottom(n = 1) {
        this.markPos0();
        this.setCursorY(this.fromy + this.height - Util.clamp(n, 0, this.height));
        this.markPos();
    }

    /* public */ cursorLeftEdge() {
        this.setCursorX(this.fromx);
    }

    /* public */ cursorMiddleColumn() {
        this.setCursorX(this.fromx + (this.width - 2) / 2);
    }

    /* public */ cursorRightEdge() {
        this.setCursorX(this.fromx + this.width - 1);
    }

    /* public */ setMark(id, x = this.cursorx, y = this.cursory) {
        if (this.iface == null)
            return false;
        return this.iface.setMark(id, x, y);
    }

    /* public */ clearMark(id) {
        if (this.iface == null)
            return false;
        return this.iface.clearMark(id);
    }

    /* public */ getMarkPos(id) {
        if (this.iface == null)
            return null;
        return this.iface.getMarkPos(id);
    }

    /* public */ findNextMark(id, x = this.cursorx, y = this.cursory) {
        if (this.iface == null)
            return false;
        return this.iface.findNextMark(id, x, y);
    }

    /* public */ findPrevMark(id, x = this.cursorx, y = this.cursory) {
        if (this.iface == null)
            return false;
        return this.iface.findPrevMark(id, x, y);
    }

    /* public */ cursorPrevWord(n) {
        return this.#cursorPrevWordImpl(ReWordEnd, n);
    }

    /* public */ cursorPrevViWord(n) {
        return this.#cursorPrevWordImpl(ReViWordEnd, n);
    }

    /* public */ cursorPrevBigWord(n) {
        return this.#cursorPrevWordImpl(ReBigWordEnd, n);
    }

    /* public */ cursorNextWord(n) {
        return this.#cursorNextWordImpl(ReWordStart, n);
    }

    /* public */ cursorNextViWord(n) {
        return this.#cursorNextWordImpl(ReViWordStart, n);
    }

    /* public */ cursorNextBigWord(n) {
        return this.#cursorNextWordImpl(ReBigWordStart, n);
    }

    /* public */ cursorWordBegin(n) {
        return this.#cursorPrevWordImpl(ReWordStart, n);
    }

    /* public */ cursorViWordBegin(n) {
        return this.#cursorPrevWordImpl(ReViWordStart, n);
    }

    /* public */ cursorBigWordBegin(n) {
        return this.#cursorPrevWordImpl(ReBigWordStart, n);
    }

    /* public */ cursorWordEnd(n) {
        return this.#cursorNextWordImpl(ReWordEnd, n);
    }

    /* public */ cursorViWordEnd(n) {
        return this.#cursorNextWordImpl(ReViWordEnd, n);
    }

    /* public */ cursorBigWordEnd(n) {
        return this.#cursorNextWordImpl(ReBigWordEnd, n);
    }

    /* public */ async getCurrentWord(x = this.cursorx, y = this.cursory) {
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
    /* public */ lowerPage(n) {
        if (n)
            this.setCursorY(n - 1);
        this.setFromY(this.cursory - this.height + 1);
    }

    /* z- */
    /* public */ lowerPageBegin(n) {
        this.lowerPage(n);
        this.cursorLineTextStart()
    }

    /* zz */
    /* public */ centerLine(n = 0) {
        if (n != 0)
            this.setCursorY(n - 1);
        this.setFromY(this.cursory - this.height / 2);
    }

    /* public */ centerColumn() {
        this.setFromX(this.cursorx - this.width / 2);
    }

    /* public */ setFromXY(x, y) {
        this.setFromY(y);
        this.setFromX(x);
    }

    /* public */ setCursorXY(x, y, refresh = true) {
        this.setCursorY(y, refresh);
        this.setCursorX(x, refresh);
    }

    /* public */ setCursorXYCenter(x, y, refresh = true) {
        const fy = this.fromy;
        const fx = this.fromx;
        this.setCursorXY(x, y, refresh);
        if (fy != this.fromy)
            this.centerLine();
        if (fx != this.fromx)
            this.centerColumn();
    }

    /* z. */
    /* public */ centerLineBegin(n) {
        this.centerLine(n);
        this.cursorLineTextStart();
    }

    /* zt */
    /* public */ raisePage(n) {
        if (n)
            this.setCursorY(n - 1);
        this.setFromY(this.cursory);
    }

    /* z^M */
    /* public */ raisePageBegin(n) {
        this.raisePage(n);
        this.cursorLineTextStart();
    }

    /* z+ */
    /* public */ nextPageBegin(n) {
        this.setCursorY(n ? n - 1 : this.fromy + this.height);
        this.cursorLineTextStart();
        this.raisePage();
    }

    /* z^ */
    /* public */ previousPageBegin(n) {
        this.setCursorY(n ? n - this.height : this.fromy - 1); /* +-1 cancels out */
        this.cursorLineTextStart();
        this.lowerPage();
    }

    /* public */ cursorToggleSelection(n = 1, opts = {}) {
        if (this.currentSelection) {
            this.clearSelection();
            return null;
        }
        const cx = this.iface?.cursorFirstX ?? 0;
        this.cursorRight(n - 1);
        return this.startSelection(opts.selectionType ?? "normal", false, cx);
    }

    /* public */ cursorLineBegin() {
        this.setCursorX(-1);
    }

    /* public */ cursorLineEnd() {
        this.setCursorX(Util.MAX_INT32);
    }

    /* public */ cursorLineTextStart() {
        const iface = this.iface;
        if (iface == null)
            return;
        const [s, e] = iface.matchFirst(/\S/, this.cursory);
        if (s >= 0) {
            const x = iface.currentLineWidth(0, s);
            this.setCursorX(x > 0 ? x : x - 1);
        } else
            this.cursorLineEnd();
    }

    /* public */ async cursorNextParagraph(n = 1) {
        const iface = this.iface;
        if (iface == null)
            return;
        this.markPos0();
        const y = await iface.findNextParagraph(this.cursory, n);
        this.setCursorY(y)
        this.markPos();
    }

    /* public */ async cursorPrevParagraph(n = 1) {
        return this.cursorNextParagraph(-n);
    }

    /* public */ async cursorNextLink(n = 1) {
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

    /* public */ async cursorPrevLink(n = 1) {
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

    /* public */ async cursorNthLink(n = 1) {
        const iface = this.iface;
        if (iface == null)
            return;
        const pos = await iface.findNextLink(0, 0, n);
        if (y >= 0)
            this.setCursorXYCenter(...pos);
    }

    /* public */ async cursorRevNthLink(n = 1) {
        const iface = this.iface;
        if (iface == null)
            return;
        const pos = await iface.findRevNthLink(n);
        if (y >= 0)
            this.setCursorXYCenter(...pos);
    }

    /* public */ async cursorLinkNavDown(n = 1) {
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

    /* public */ async cursorLinkNavUp(n = 1) {
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

    /* public */ cursorFirstLine() {
        this.markPos0();
        this.setCursorY(0);
        this.markPos();
    }

    /* public */ cursorLastLine() {
        this.markPos0();
        this.setCursorY(this.numLines - 1);
        this.markPos();
    }

    /* public */ gotoMark(id) {
        const pos = this.getMarkPos(id);
        if (pos == null)
            return false;
        this.markPos0();
        this.setCursorXYCenter(...pos);
        this.markPos();
        return true;
    }

    /* public */ gotoMarkY(id) {
        const pos = this.getMarkPos(id);
        if (pos == null)
            return false;
        this.markPos0();
        this.setCursorXYCenter(0, pos[1]);
        this.markPos();
        return true;
    }

    /* public */ setCursorYCenter(y) {
        const fy = this.fromy;
        this.setCursorY(y);
        if (fy != this.fromy)
            this.centerLine();
    }

    /* public */ setCursorXCenter(x) {
        const fx = this.fromx;
        this.setCursorX(x);
        if (fx != this.fromx)
            this.centerColumn();
    }

    /* public */ setAbsoluteCursorXY(x, y) {
        this.setCursorXY(this.fromx + x, this.fromy + y);
    }

    /* public */ async markURL() {
        const iface = this.iface;
        if (iface == null)
            return;
        await iface.markURL();
        return this.sendCursorPosition();
    }

    /* public */ reshape() {
        const iface = this.iface;
        if (iface == null)
            return;
        if (pager.bufferInit == this.init)
            pager.setVisibleBuffer(this);
        return iface.forceReshape();
    }

    /* public */ editSource() {
        const url = pager.url;
        const path = url.protocol == "file:" ?
            decodeURIComponent(url.pathname) :
            pager.cacheFile;
        const cmd = pager.getEditorCommand(path)
        pager.extern(cmd);
    }

    /* public */ saveSource() {
        pager.gotoURL("cache:" + this.cacheId, {save: true, url: this.url});
    }

    /* public */ async toggleImages() {
        const iface = this.iface;
        if (iface == null)
            return;
        this.init.images = await iface.toggleImages();
    }

    /* public */ async click(n = 1) {
        const iface = this.iface;
        if (iface == null)
            return;
        const res = await iface.click(this.cursorx, this.cursory, n);
        return this.#onclick(res);
    }

    /* public */ async saveLink() {
        const iface = this.iface;
        if (iface == null)
            return;
        const res = await iface.click(this.cursorx, this.cursory, 1);
        return this.#onclick(res, true);
    }

    /* public */ showLinkHints = async function() {
        const iface = this.iface;
        if (iface == null)
            return [];
        const sx = this.fromx;
        const sy = this.fromy;
        const ex = sx + this.width;
        const ey = sy + this.height;
        return iface.showHints(sx, sy, ex, ey);
    }

    /* private */ hideLinkHints() {
        const iface = this.iface;
        if (iface == null)
            return;
        return iface.hideHints();
    }

    /* private */ contextMenu() {
        const iface = this.iface;
        if (iface == null)
            return;
        return iface.contextMenu(this.cursorx, this.cursory);
    }

    /* public */ getSelectionText(sel = this.currentSelection) {
        const iface = this.iface;
        if (iface == null || sel == null)
            return "";
        return iface.getSelectionText(sel.startx, sel.starty, sel.endx,
                                      sel.endy, sel.selectionType)
    }

    /* public */ async saveScreen() {
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

    /* public */ async editScreen() {
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
}
