/*
 * Example menu file.
 *
 * Usage: put it in ~/.chawan/menu.js, customize to your liking, then bind
 * a key in ~/.chawan/config.toml like

c = '() => pager.menu ? pager.closeMenu() : pager.openCustomMenu({name: "mainMenu"})'
's b' = '() => pager.openCustomMenu({name: "bufferMenu"})'

 * Similarly, you can define new menus too; just export another function
 * and use its name in `openCustomMenu`.
 */

export function mainMenu(m) {
    if (buffer?.currentSelection != null)
        m.item("Copy selection           (y)", cmd.copySelection, "v")
    else
        m.item("Select text              (v)", cmd.cursorToggleSelection, "v")
    m.menu("Select buffer          (s b)",
            () => pager.openCustomMenu({name: "bufferMenu"}), "s b")
    m.line()
    m.item("Copy page URL          (M-y)", cmd.copyURL, "M-y")
    m.item("Copy link              (y u)", cmd.copyCursorLink, "y u")
    m.item("View image               (I)", cmd.viewImage, "I")
    m.item("Copy image link        (y I)", cmd.copyCursorImage, "y I")
    m.item("Reload                   (U)", cmd.reloadBuffer, "U")
    m.line()
    m.item("Save link            (s RET)", cmd.saveLink, "s RET")
    m.item("View source              (\\)", cmd.toggleSource, "\\")
    m.item("Edit source            (s E)", cmd.editSource, "s E")
    m.item("Save source            (s S)", cmd.saveSource, "s S")
    m.line()
    m.item("Linkify URLs             (:)", cmd.markURL, ":")
    m.item("Toggle images          (M-i)", cmd.toggleImages, "M-i")
    m.item("Toggle JS & reload     (M-j)", cmd.toggleScripting, "M-j")
    m.item("Toggle cookie & reload (M-k)", cmd.toggleCookie, "M-k")
    m.line()
    m.item("Bookmark page          (M-a)", cmd.addBookmark, "M-a")
    m.item("Open bookmarks         (M-b)", cmd.openBookmarks, "M-b")
    m.item("Open history           (C-h)", cmd.openHistory, "C-h")
    m.line()
    m.item("Force-quit browser       (q)", cmd.quit, "q")
}

export function bufferMenu(m) {
    for (let buffer = pager.tab.head; buffer != null; buffer = buffer.next) {
        m.item(buffer.url, () => pager.setBuffer(buffer));
        if (buffer == pager.buffer)
            m.select();
    }
    m.bind(() => { select.cursorUp(); cmd.prevBuffer() }, ",");
    m.bind(() => { select.cursorDown(); cmd.nextBuffer() }, ".");
    m.bind(() => {
        cmd.discardBuffer()
        select.cancel()
        cmd.openBufferMenu()
    }, "D");
    m.line()
    m.line("comma (,)/period (.): previous/next │ D: delete");
}
