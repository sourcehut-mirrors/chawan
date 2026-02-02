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
    sourceEdit: () => {
        const url = pager.url;
        pager.extern(pager.getEditorCommand(url.protocol == "file:" ?
            decodeURIComponent(url.pathname) :
            pager.cacheFile));
    },
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
        "cursorRevNthLink", "peekCursor"]) {
    cmd[it] = n => pager[it](n);
}

/* pager, no precnum */
for (const it of ["markURL", "redraw", "reshape", "cancel", "toggleSource",
        "nextBuffer", "prevBuffer", "cursorLineBegin", "cursorLineTextStart",
        "cursorLineEnd", "lineInfo", "discardBuffer", "discardBufferTree",
        "cursorMiddleColumn", "cursorLeftEdge", "cursorRightEdge",
        "cursorMiddle", "searchForward", "searchBackward", "isearchForward",
        "isearchBackward", "discardTree", "dupeBuffer", "load", "loadCursor",
        "saveLink", "saveSource", "toggleImages", "writeInputBuffer",
        "showFullAlert", "toggleLinkHints"]) {
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
 * Maximum number of consequent clicks registered.
 * Sort of a product of poor design.
 */
const MAX_CLICKS = 3;

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

function addDefaultOmniRule(name, match, url) {
    const fun = x => url + encodeURIComponent(x.substring(x.indexOf(':')));
    config.addOmniRule(name, match, fun);
}

Pager.prototype.init = function() {
    this.mouse = new Mouse();
    this.commandMode = false;
    addDefaultOmniRule("ddg", /^ddg:/,
        "https://lite.duckduckgo.com/lite/?kp=-1&kd=-1&q=");
    addDefaultOmniRule("br", /^br:/, "https://search.brave.com/search?q=");
    addDefaultOmniRule("wk", /^wk:/,
        "https://en.wikipedia.org/wiki/Special:Search?search=");
    addDefaultOmniRule("wd", /^wd:/,
        "https://en.wiktionary.org/w/index.php?title=Special:Search&search=");
    addDefaultOmniRule("mo", /^mo:/, "https://mojeek.com/search?q=");
}

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
    if (url == null) {
        if (!this.buffer)
            return;
        url = this.buffer.url;
    }
    const res = await this.setLineEdit("location", "URL: ", {current: url});
    if (res)
        this.loadSubmit(res);
}

Pager.prototype.loadCursor = function() {
    return this.load(this.hoverLink || this.hoverImage);
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

Pager.prototype.handleMouseInput = async function(input) {
    if (this.mouse.blockTillRelease) {
        if (input.t != "release")
            return;
        this.mouse.blockTillRelease = false;
    }
    const button = input.button;
    const [pressedX, pressedY] = this.mouse.pressed[button] ?? [-1, -1];
    let buffer = this.buffer;
    const select = this.menu ?? buffer?.select;
    if (select != null) {
        /* one off because of border */
        const y = select.fromy + input.y - select.y - 1;
        let inside =
            select.y + 1 <= input.y && input.y < select.y + select.height - 1 &&
            select.x + 1 <= input.x && input.x < select.x + select.width - 1;
        let outside = select.y > input.y || input.y >= select.y + select.height &&
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
                    this.mouse.blockTillRelease = true;
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
                    this.mouse.blockTillRelease = true;
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
                if (this.mouse.click[button] < 1)
                    break;
                switch (this.mouse.moveType) {
                case "none":
                    if (pressedY == input.y) {
                        this.mouse.moveType = "select";
                        if (!buffer.hasMouseSelection())
                            await buffer.startSelection("normal", true);
                        buffer.setAbsoluteCursorXY(input.x, input.y);
                    } else
                        this.mouse.moveType = "drag";
                    break;
                case "select":
                    buffer.setAbsoluteCursorXY(input.x, input.y);
                    break;
                }
                break;
            case "release":
                if (buffer.hasMouseSelection()) {
                    this.mouse.inSelection = true;
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
                        buffer.click(this.mouse.click[button]);
                }
                this.mouse.moveType = "none";
                break;
            case "press":
                if (buffer.hasMouseSelection())
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
    if (!this.mouse.blockTillRelease) {
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
                    else
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
            this.mouse.pressed[button] = [input.x, input.y];
            const [releasedX, releasedY] =
                this.mouse.released[button] ?? [-1, -1];
            if (input.x == releasedX && input.y == releasedY) {
                this.mouse.click[button] ??= 0;
                if (++this.mouse.click[button] >= MAX_CLICKS)
                    this.mouse.click[button] = 0;
            }
            break;
        case "release":
            if (pressedX != input.x || pressedY != input.y)
                this.mouse.click[button] = 0;
            this.mouse.released[button] = this.mouse.pressed[button];
            this.mouse.pressed[button] = [-1, -1];
            break;
        }
    }
    this.queueStatusUpdate();
    this.handleEvents();
}

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
            if (map.keyLast == 0) {
                this.precnum = 0;
                await p;
                this.queueStatusUpdate();
                this.handleEvents();
            } else
                this.queueStatusUpdate();
        }
        break;
    case "mouse":
        return this.handleMouseInput(mouseInput);
    }
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

Buffer.prototype.cursorNextParagraph = async function(n = 1) {
    const iface = this.iface;
    if (iface == null)
        return;
    this.markPos0();
    const y = await iface.findNextParagraph(this.cursory, n);
    this.setCursorY(y)
    this.markPos();
}

Buffer.prototype.cursorPrevParagraph = async function(n = 1) {
    return this.cursorNextParagraph(-n);
}

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

Buffer.prototype.cursorNthLink = async function(n = 1) {
    const iface = this.iface;
    if (iface == null)
        return;
    const pos = await iface.findNextLink(0, 0, n);
    if (y >= 0)
        this.setCursorXYCenter(...pos);
}

Buffer.prototype.cursorRevNthLink = async function(n = 1) {
    const iface = this.iface;
    if (iface == null)
        return;
    const pos = await iface.findRevNthLink(n);
    if (y >= 0)
        this.setCursorXYCenter(...pos);
}

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

Buffer.prototype.cursorLinkNavUp = async function(n = 1) {
    const iface = this.iface;
    if (iface == null)
        return;
    const [x, y] = await iface.findPrevLink(this.cursorx, this.cursory, n);
    if (y < 0) {
        const numLines = this.numLines;
        if (numLines <= this.height) {
            const [x2, y2] = await iface.findPrevLink(MAX_INT32,
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

Buffer.prototype.cursorLastLine = function() {
    this.markPos0();
    this.setCursorY(this.numLines - 1);
    this.markPos();
}

Buffer.prototype.gotoMark = function(id) {
    const pos = this.getMarkPos(id);
    if (pos == null)
        return false;
    this.markPos0();
    this.setCursorXYCenter(...pos);
    this.markPos();
    return true;
}

Buffer.prototype.gotoMarkY = function(id) {
    const pos = this.getMarkPos(id);
    if (pos == null)
        return false;
    this.markPos0();
    this.setCursorXYCenter(0, pos[1]);
    this.markPos();
    return true;
}

Buffer.prototype.setCursorYCenter = function(y) {
    const fy = this.fromy;
    this.setCursorY(y);
    if (fy != this.fromy)
        this.centerLine();
}

Buffer.prototype.setCursorXCenter = function(x) {
    const fx = this.fromx;
    this.setCursorX(x);
    if (fx != fromx)
        this.centerColumn();
}

Buffer.prototype.setAbsoluteCursorXY = function(x, y) {
    this.setCursorXY(this.fromx + x, this.fromy + y);
}

Buffer.prototype.markURL = async function() {
    const iface = this.iface;
    if (iface == null)
        return;
    await iface.markURL();
    return this.sendCursorPosition();
}

Buffer.prototype.reshape = function() {
    const iface = this.iface;
    if (iface == null)
        return;
    return iface.forceReshape();
}

Buffer.prototype.saveSource = function() {
    pager.gotoURL("cache:" + this.cacheId, {save: true, url: this.url});
}
