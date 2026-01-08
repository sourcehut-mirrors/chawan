async function toggleLinkHints() {
    pager.markPos0();
    const urls = await pager.showLinkHints();
    if (urls.length == 0) {
        pager.alert("No links on page");
        return;
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
            it = it[h[k]] ?? (it[h[k]] = {});
        urls[i].leaf = true;
        it[h.at(-1)] = urls[i];
    }
    let s = "";
    let it = map;
    let alert = true;
    while (it && !it.leaf) {
        const c = await pager.askChar(s);
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
    pager.hideLinkHints();
    if (it?.leaf) {
        pager.setCursorXY(it.x, it.y);
        pager.markPos();
    } else if (alert)
        pager.alert("No such hint");
}

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
        const url = `cgi-bin:chabookmark?url=${encodeURIComponent(pager.url)}&title=${encodeURIComponent(pager.title)}`;
        pager.gotoURL(url);
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
    prevSiblingBuffer: () => pager.prevSiblingBuffer(),
    nextBuffer: () => pager.nextBuffer(),
    nextSiblingBuffer: () => pager.nextSiblingBuffer(),
    parentBuffer: () => pager.parentBuffer(),
    enterCommand: () => pager.command(),
    searchForward: () => pager.searchForward(),
    searchBackward: () => pager.searchBackward(),
    isearchForward: () => pager.isearchForward(),
    isearchBackward: () => pager.isearchBackward(),
    searchNext: n => pager.searchNext(n),
    searchPrev: n => pager.searchPrev(n),
    toggleCommandMode: () => {
        if ((pager.commandMode = consoleBuffer != pager.buffer))
            console.show();
        else
            console.hide();
    },
    showFullAlert: () => pager.showFullAlert(),
    toggleLinkHints: toggleLinkHints,
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
    gotoLineOrEnd: n => n ? pager.gotoLine(n) : pager.cursorLastLine(),
    /* vim gg */
    gotoLineOrStart: n => n ? pager.gotoLine(n) : pager.cursorFirstLine(),
    /* vi | */
    gotoColumnOrBegin: n => n ? pager.setCursorXCenter(n - 1) : pager.cursorLineBegin(),
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
