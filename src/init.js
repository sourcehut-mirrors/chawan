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
    peek: () => pager.alert(pager.url),
    peekCursor: n => pager.peekCursor(n),
    toggleWrap: () => {
        config.search.wrap = !config.search.wrap;
        pager.alert("Wrap search " + (config.search.wrap ? "on" : "off"));
    },
    dupeBuffer: () => pager.dupeBuffer(),
    load: () => pager.load(),
    loadCursor: () => pager.load(pager.hoverLink || pager.hoverImage),
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
    lineInfo: () => pager.lineInfo(),
    toggleSource: () => pager.toggleSource(),
    discardBuffer: () => pager.discardBuffer(),
    discardBufferPrev: () => pager.discardBuffer(pager.buffer, "prev"),
    discardBufferNext: () => pager.discardBuffer(pager.buffer, "next"),
    discardTree: () => pager.discardTree(),
    prevBuffer: () => pager.prevBuffer(),
    nextBuffer: () => pager.nextBuffer(),
    enterCommand: () => pager.command(),
    searchForward: () => pager.searchForward(),
    searchBackward: () => pager.searchBackward(),
    isearchForward: () => pager.isearchForward(),
    isearchBackward: () => pager.isearchBackward(),
    searchNext: n => pager.searchNext(n),
    searchPrev: n => pager.searchPrev(n),
    toggleCommandMode: () => {
        if ((pager.commandMode = consoleBuffer != pager.buffer)) {
            if (!line)
                pager.command();
            console.show();
        } else
            console.hide();
    },
    showFullAlert: () => pager.showFullAlert(),
    toggleLinkHints: () => pager.toggleLinkHints(),
    toggleLinkHintsAutoClick: async () => {
        const res = await pager.toggleLinkHints();
        if (res)
            pager.click();
    },
    cursorLeft: n => pager.cursorLeft(n),
    cursorDown: n => pager.cursorDown(n),
    cursorUp: n => pager.cursorUp(n),
    cursorRight: n => pager.cursorRight(n),
    cursorLineBegin: () => pager.cursorLineBegin(),
    cursorLineTextStart: () => pager.cursorLineTextStart(),
    cursorLineEnd: () => pager.cursorLineEnd(),
    cursorNextWord: () => pager.cursorNextWord(),
    cursorNextViWord: () => pager.cursorNextViWord(),
    cursorNextBigWord: () => pager.cursorNextBigWord(),
    cursorWordBegin: () => pager.cursorWordBegin(),
    cursorViWordBegin: () => pager.cursorViWordBegin(),
    cursorBigWordBegin: () => pager.cursorBigWordBegin(),
    cursorWordEnd: () => pager.cursorWordEnd(),
    cursorViWordEnd: () => pager.cursorViWordEnd(),
    cursorBigWordEnd: () => pager.cursorBigWordEnd(),
    cursorPrevLink: n => pager.cursorPrevLink(n),
    cursorNextLink: n => pager.cursorNextLink(n),
    cursorPrevParagraph: n => pager.cursorPrevParagraph(n),
    cursorNextParagraph: n => pager.cursorNextParagraph(n),
    cursorTop: n => pager.cursorTop(n),
    cursorMiddle: () => pager.cursorMiddle(),
    cursorBottom: n => pager.cursorBottom(n),
    cursorLeftEdge: () => pager.cursorLeftEdge(),
    cursorMiddleColumn: () => pager.cursorMiddleColumn(),
    cursorRightEdge: () => pager.cursorRightEdge(),
    halfPageDown: n => pager.halfPageDown(n),
    halfPageUp: n => pager.halfPageUp(n),
    halfPageLeft: n => pager.halfPageLeft(n),
    halfPageRight: n => pager.halfPageRight(n),
    pageDown: n => pager.pageDown(n),
    pageUp: n => pager.pageUp(n),
    pageLeft: n => pager.pageLeft(n),
    pageRight: n => pager.pageRight(n),
    scrollDown: n => pager.scrollDown(n),
    scrollUp: n => pager.scrollUp(n),
    scrollLeft: n => pager.scrollLeft(n),
    scrollRight: n => pager.scrollRight(n),
    click: n => pager.click(n),
    rightClick: async () => {
        if (!pager.menu) {
            const canceled = await pager.contextMenu();
            if (!canceled)
                pager.openMenu()
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
    toggleImages: () => pager.toggleImages(),
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
    markURL: () => pager.markURL(),
    redraw: () => pager.redraw(),
    reshape: () => pager.reshape(),
    cancel: () => pager.cancel(),
    /* vi G */
    gotoLineOrEnd: n => pager.gotoLine(n ?? pager.numLines),
    /* vim gg */
    gotoLineOrStart: n => pager.gotoLine(n ?? 1),
    /* vi | */
    gotoColumnOrBegin: n => pager.setCursorXCenter((n ?? 1) - 1),
    gotoColumnOrEnd: n => n ? pager.setCursorXCenter(n - 1) : pager.cursorLineEnd(),
    /* vi z. z^M z- */
    centerLineBegin: n => pager.centerLineBegin(n),
    raisePageBegin: n => pager.raisePageBegin(n),
    lowerPageBegin: n => pager.lowerPageBegin(n),
    /* vi z+ z^ */
    nextPageBegin: n => pager.nextPageBegin(n),
    previousPageBegin: n => pager.previousPageBegin(n),
    /* vim zz zb zt */
    centerLine: n => pager.centerLine(n),
    raisePage: n => pager.raisePage(n),
    lowerPage: n => pager.lowerPage(n),
    cursorToggleSelection: n => pager.cursorToggleSelection(n),
    selectOrCopy: n => {
        if (pager.currentSelection)
            cmd.buffer.copySelection();
        else
            pager.cursorToggleSelection(n)
    },
    cursorToggleSelectionLine: n => pager.cursorToggleSelection(n, {selectionType: "line"}),
    cursorToggleSelectionBlock: n => pager.cursorToggleSelection(n, {selectionType: "block"}),
    sourceEdit: () => {
        const url = pager.url;
        pager.extern(pager.getEditorCommand(url.protocol == "file:" ?
            decodeURIComponent(url.pathname) :
            pager.cacheFile));
    },
    saveLink: () => pager.saveLink(),
    saveSource: () => pager.saveSource(),
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
        const text = await pager.getSelectionText(pager.currentSelection);
        const s = text.length != 1 ? "s" : "";
        if (pager.clipboardWrite(text))
            pager.alert(`Copied ${text.length} character${s}.`);
        else
            pager.alert("Error; please install xsel or adjust external.copy-cmd");
        pager.cursorToggleSelection();
    },
    cursorNthLink: n => pager.cursorNthLink(n),
    cursorRevNthLink: n => pager.cursorRevNthLink(n),
    line: {
        submit: () => line.submit(),
        backspace: () => line.backspace(),
        delete: () => line.delete(),
        cancel: () => line.cancel(),
        prevWord: () => line.prevWord(),
        nextWord: () => line.nextWord(),
        backward: () => line.backward(),
        forward: () => line.forward(),
        clear: () => line.clear(),
        kill: () => line.kill(),
        clearWord: () => line.clearWord(),
        killWord: () => line.killWord(),
        begin: () => line.begin(),
        end: () => line.end(),
        escape: () => line.escape(),
        prevHist: () => line.prevHist(),
        nextHist: () => line.nextHist(),
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

/* backwards compat: cmd.pager and cmd.buffer used to be separate */
cmd.pager = cmd.buffer = cmd;

/*
 * Utils
 */
function clamp(n, lo, hi) {
    return Math.min(Math.max(n, lo), hi);
}

/*
 * Used as a substitute for int.high.
 * TODO: might want to use Number.MAX_SAFE_INTEGER, but I'm not sure if
 * fromJS for int saturates.  (If it doesn't, just change everything to
 * int64.)
 */
const MAX_INT32 = 0xFFFFFFFF;

/*
 * Pager
 */

/*
 * Emulate vim's \c/\C: override defaultFlags if one is found, then remove
 * it from str.
 * Also, replace \< and \> with \b as (a bit sloppy) vi emulation.
 */
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

Pager.prototype.setSearchRegex = function(s, flags, reverse = false) {
    if (!flags.includes('g'))
        flags += 'g';
    this.regex = new RegExp(s, flags);
    this.reverseSearch = reverse;
}

Pager.prototype.searchNext = async function(n = 1) {
    const regex = this.regex;
    if (regex) {
        let wrap = config.search.wrap;
        /* TODO probably we should add a separate keymap for menu/select */
        if (this.menu)
            return this.menu.cursorNextMatch(this.regex, wrap, true, n);
        const buffer = this.buffer;
        buffer.markPos0();
        if (!this.reverseSearch)
            await buffer.cursorNextMatch(regex, wrap, true, n);
        else
            await buffer.cursorPrevMatch(regex, wrap, true, n);
        buffer.markPos();
    } else
        this.alert("No previous regular expression");
}

Pager.prototype.searchPrev = async function(n = 1) {
    if (this.regex) {
        let wrap = config.search.wrap;
        /* TODO ditto */
        if (this.menu)
            return this.menu.cursorPrevMatch(this.regex, wrap, true, n);
        const buffer = this.buffer;
        buffer.markPos0();
        if (!this.reverseSearch)
            await buffer.cursorPrevMatch(this.regex, wrap, true, n);
        else
            await buffer.cursorNextMatch(this.regex, wrap, true, n);
        buffer.markPos();
    } else
        this.alert("No previous regular expression");
}

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

Pager.prototype.searchBackward = function() {
    return this.searchForward(true);
}

Pager.prototype.isearchForward = async function(reverse = false) {
    const buffer = this.buffer;
    if (this.menu || buffer?.select) {
        /* isearch doesn't work in menus. */
        this.searchForward(reverse)
    } else if (buffer) {
        buffer.pushCursorPos()
        buffer.markPos0()
        const text = await this.setLineEdit("search", reverse ? "?" : "/", {
            update: (async function() {
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
                    const [x, y, w] = await (reverse ?
                        buffer.findPrevMatch(re, cx, cy, wrap, 1) :
                        buffer.findNextMatch(re, cx, cy, wrap, 1));
                    if (this.isearchIter === iter)
                        buffer.onMatch(x, y, w, false);
                }
            }).bind(this)
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
        buffer.clearSearchHighlights()
        buffer.queueDraw();
    }
}

Pager.prototype.isearchBackward = function() {
    return this.isearchForward(true);
}

/* Reuse the line editor as an alert message viewer. */
Pager.prototype.showFullAlert = function() {
    const str = this.lastAlert;
    if (str != "")
        this.setLineEdit("alert", "", {current: str});
}

/* Open a URL prompt. */
Pager.prototype.load = async function(url = null) {
    if (!url) {
        if (!this.buffer)
            return;
        url = this.buffer.url;
    }
    const res = await this.setLineEdit("location", "URL: ", {current: url});
    if (res)
        this.loadSubmit(res);
}

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
            n = MAX_INT32;
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


/*
 * Buffer
 *
 * TODO: this should be a separate class from Container, and Container
 * should be renamed to BufferInterface.
 */

Buffer.prototype.cursorDown = function(n = 1) {
    this.setCursorY(this.cursory + n);
}

Buffer.prototype.cursorUp = function(n = 1) {
    this.setCursorY(this.cursory - n);
}

Buffer.prototype.cursorLeft = function(n = 1) {
    this.setCursorX(this.cursorFirstX() - n);
}

Buffer.prototype.cursorRight = function(n = 1) {
    this.setCursorX(this.cursorLastX() + n);
}

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

Buffer.prototype.scrollRight = function(n = 1) {
    const msw = this.maxScreenWidth();
    const x = Math.min(this.fromx + this.width + n, msw) - this.width;
    if (x > this.fromx)
        this.setFromX(x);
}

Buffer.prototype.scrollLeft = function(n = 1) {
    const x = Math.max(this.fromx - n, 0);
    if (x < this.fromx)
        this.setFromX(x);
}

Buffer.prototype.pageDown = function(n = 1) {
    const delta = this.height * n;
    this.setFromY(this.fromy + delta);
    this.setCursorY(this.cursory + delta);
    this.restoreCursorX();
}

Buffer.prototype.pageUp = function(n = 1) {
    this.pageDown(-n);
}

Buffer.prototype.pageLeft = function(n = 1) {
    this.setFromX(this.fromx - this.width * n);
}

Buffer.prototype.pageRight = function(n = 1) {
    this.setFromX(this.fromx + this.width * n);
}

/* I am not cloning the vi behavior of e.g. 2^D setting paging size because
 * it is counter-intuitive and annoying. */
Buffer.prototype.halfPageDown = function(n = 1) {
    const delta = (this.height + 1) / 2 * n;
    this.setFromY(this.fromy + delta);
    this.setCursorY(this.cursory + delta);
    this.restoreCursorX();
}

Buffer.prototype.halfPageUp = function(n = 1) {
    this.halfPageDown(-n);
}

Buffer.prototype.halfPageLeft = function(n = 1) {
    this.setFromX(this.fromx - (this.width + 1) / 2 * n);
}

Buffer.prototype.halfPageRight = function(n = 1) {
    this.setFromX(this.fromx + (this.width + 1) / 2 * n);
}

Buffer.prototype.cursorTop = function(n = 1) {
    this.markPos0();
    this.setCursorY(this.fromy + clamp(n - 1, 0, this.height - 1));
    this.markPos();
}

Buffer.prototype.cursorMiddle = function() {
    this.markPos0();
    this.setCursorY(this.fromy + (this.height - 2) / 2);
    this.markPos();
}

Buffer.prototype.cursorBottom = function(n = 1) {
    this.markPos0();
    this.setCursorY(this.fromy + this.height - clamp(n, 0, this.height));
    this.markPos();
}

Buffer.prototype.cursorLeftEdge = function() {
    this.setCursorX(this.fromx);
}

Buffer.prototype.cursorMiddleColumn = function() {
    this.setCursorX(this.fromx + (this.width - 2) / 2);
}

Buffer.prototype.cursorRightEdge = function() {
    this.setCursorX(this.fromx + this.width - 1);
}

Buffer.prototype.onMatch = function(x, y, w, refresh) {
    if (y >= 0) {
        this.setCursorXYCenter(x, y, refresh);
        if (this.highlight) {
            this.clearSearchHighlights();
            this.addSearchHighlight(x, y, x + w - 1, y);
            this.queueDraw();
            this.highlight = false;
        }
    } else if (this.highlight) {
        this.clearSearchHighlights();
        this.queueDraw();
        this.highlight = false;
    }
}

Buffer.prototype.cursorNextMatch = async function(re, wrap, refresh, n) {
    if (this.select)
        return this.select.cursorNextMatch(re, wrap, n);
    const cx = this.cursorx;
    const cy = this.cursory;
    const [x, y, w] = await this.findNextMatch(re, cx, cy, wrap, n);
    this.onMatch(x, y, w, refresh);
}

Buffer.prototype.cursorPrevMatch = async function(re, wrap, refresh, n) {
    if (this.select)
        return this.select.cursorPrevMatch(re, wrap, n);
    const cx = this.cursorx;
    const cy = this.cursory;
    const [x, y, w] = await this.findPrevMatch(re, cx, cy, wrap, n);
    this.onMatch(x, y, w, refresh);
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

Buffer.prototype.cursorPrevWordImpl = async function(re, n = 1) {
    const cx = this.cursorx;
    const cy = this.cursory;
    const [x, y, w] = await this.findPrevMatch(re, cx, cy, false, n);
    if (y >= 0)
        this.setCursorXY(x + w - 1, y);
    else
        this.cursorLineBegin();
}

Buffer.prototype.cursorNextWordImpl = async function(re, n = 1) {
    const cx = this.cursorx;
    const cy = this.cursory;
    const [x, y, w] = await this.findNextMatch(re, cx, cy, false, n);
    if (y >= 0 && x >= 0)
        this.setCursorXY(x + w - 1, y);
    else
        this.cursorLineEnd();
}

Buffer.prototype.cursorPrevWord = function(n) {
    return this.cursorPrevWordImpl(ReWordEnd, n);
}

Buffer.prototype.cursorPrevViWord = function(n) {
    return this.cursorPrevWordImpl(ReViWordEnd, n);
}

Buffer.prototype.cursorPrevBigWord = function(n) {
    return this.cursorPrevWordImpl(ReBigWordEnd, n);
}

Buffer.prototype.cursorNextWord = function(n) {
    return this.cursorNextWordImpl(ReWordStart, n);
}

Buffer.prototype.cursorNextViWord = function(n) {
    return this.cursorNextWordImpl(ReViWordStart, n);
}

Buffer.prototype.cursorNextBigWord = function(n) {
    return this.cursorNextWordImpl(ReBigWordStart, n);
}

Buffer.prototype.cursorWordBegin = function(n) {
    return this.cursorPrevWordImpl(ReWordStart, n);
}

Buffer.prototype.cursorViWordBegin = function(n) {
    return this.cursorPrevWordImpl(ReViWordStart, n);
}

Buffer.prototype.cursorBigWordBegin = function(n) {
    return this.cursorPrevWordImpl(ReBigWordStart, n);
}

Buffer.prototype.cursorWordEnd = function(n) {
    return this.cursorNextWordImpl(ReWordEnd, n);
}

Buffer.prototype.cursorViWordEnd = function(n) {
    return this.cursorNextWordImpl(ReViWordEnd, n);
}

Buffer.prototype.cursorBigWordEnd = function(n) {
    return this.cursorNextWordImpl(ReBigWordEnd, n);
}

/* zb */
Buffer.prototype.lowerPage = function(n) {
    if (n)
        this.setCursorY(n - 1);
    this.setFromY(this.cursory - this.height + 1);
}

/* z- */
Buffer.prototype.lowerPageBegin = function(n) {
    this.lowerPage(n);
    this.cursorLineTextStart()
}

/* TODO centerLine */

/* z. */
Buffer.prototype.centerLineBegin = function(n) {
    this.centerLine(n);
    this.cursorLineTextStart();
}

/* zt */
Buffer.prototype.raisePage = function(n) {
    if (n)
        this.setCursorY(n - 1);
    this.setFromY(this.cursory);
}

/* z^M */
Buffer.prototype.raisePageBegin = function(n) {
    this.raisePage(n);
    this.cursorLineTextStart();
}

/* z+ */
Buffer.prototype.nextPageBegin = function(n) {
    this.setCursorY(n ? n - 1 : this.fromy + this.height);
    this.cursorLineTextStart();
    this.raisePage();
}

/* z^ */
Buffer.prototype.previousPageBegin = function(n) {
    this.setCursorY(n ? n - this.height : this.fromy - 1); /* +-1 cancels out */
    this.cursorLineTextStart();
    this.lowerPage();
}

Buffer.prototype.cursorToggleSelection = function(n = 1, opts = {}) {
    if (this.currentSelection) {
        this.clearSelection();
        return null;
    }
    const cx = this.cursorFirstX();
    this.cursorRight(n - 1);
    return this.startSelection(opts.selectionType ?? "normal", false, cx);
}

Buffer.prototype.cursorLineBegin = function() {
    this.setCursorX(-1);
}

Buffer.prototype.cursorLineEnd = function() {
    this.setCursorX(MAX_INT32);
}

Buffer.prototype.cursorLineTextStart = function() {
    const [s, e] = this.matchFirst(/\S/);
    if (s >= 0) {
        const x = this.currentLineWidth(0, s);
        this.setCursorX(x > 0 ? x : x - 1);
    } else
        this.cursorLineEnd();
}

Buffer.prototype.cursorNextLink = async function(n = 1) {
    this.markPos0();
    const [x, y] = await this.findNextLink(this.cursorx, this.cursory, n);
    if (y >= 0) {
        this.setCursorXY(x, y);
        this.markPos();
    }
}

Buffer.prototype.cursorPrevLink = async function(n = 1) {
    this.markPos0();
    const [x, y] = await this.findPrevLink(this.cursorx, this.cursory, n);
    if (y >= 0) {
        this.setCursorXY(x, y);
        this.markPos();
    }
}

Buffer.prototype.cursorLinkNavDown = async function(n = 1) {
    this.markPos0();
    const [x, y] = await this.findNextLink(this.cursorx, this.cursory, n);
    if (y < 0) {
        if (this.numLines <= this.height) {
            const [x2, y2] = await this.findNextLink(-1, 0, 1);
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

Buffer.prototype.cursorLinkNavUp = async function(n = 1) {
    const [x, y] = await this.findPrevLink(this.cursorx, this.cursory, n);
    if (y < 0) {
        const numLines = this.numLines;
        if (numLines <= this.height) {
            const [x2, y2] = await this.findPrevLink(MAX_INT32,
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

Buffer.prototype.cursorFirstLine = function() {
    this.markPos0();
    this.setCursorY(0);
    this.markPos();
}
