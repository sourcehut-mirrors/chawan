# Generic object for line editing and browsing hist.
import std/posix
import std/tables

import io/dynstream
import utils/twtstr

type
  History* = ref object
    first*: HistoryEntry
    last*: HistoryEntry
    mtime*: int64
    map: Table[string, HistoryEntry]
    len: int
    maxLen: int

  HistoryEntry* = ref object
    s*: string
    prev* {.cursor.}: HistoryEntry
    next*: HistoryEntry

proc add(hist: History; entry: sink HistoryEntry) =
  let old = hist.map.getOrDefault(entry.s)
  if old != nil:
    if hist.first == old:
      hist.first = old.next
    if hist.last == old:
      hist.last = old.prev
    let prev = old.prev
    if prev != nil:
      prev.next = old.next
    if old.next != nil:
      old.next.prev = prev
    dec hist.len
  if hist.first == nil:
    hist.first = entry
  else:
    entry.prev = hist.last
    hist.last.next = entry
  hist.map[entry.s] = entry
  hist.last = entry
  inc hist.len
  if hist.len > hist.maxLen:
    if hist.first.next != nil:
      hist.first.next.prev = nil
    hist.first = hist.first.next
    if hist.first == nil:
      hist.last = nil
    dec hist.len

func newHistory*(maxLen: int; mtime = 0i64): History =
  return History(maxLen: maxLen, mtime: mtime)

proc add*(hist: History; s: sink string) =
  hist.add(HistoryEntry(s: s))

proc parse(hist: History; iq: openArray[char]) =
  var i = 0
  while i < iq.len:
    let s = iq.until('\n', i)
    i += s.len + 1
    hist.add(s)

# Consumes `ps'.
proc parse*(hist: History; ps: PosixStream; mtime: int64) =
  let src = ps.readAllOrMmap()
  hist.parse(src.toOpenArray())
  hist.mtime = mtime
  deallocMem(src)
  ps.sclose()

proc c_rename(oldname, newname: cstring): cint {.importc: "rename",
  header: "<stdio.h>".}

# Consumes `ps'.
proc write*(hist: History; ps: PosixStream; sync, reverse: bool): bool =
  var buf = ""
  var entry = if reverse: hist.last else: hist.first
  var res = true
  while entry != nil:
    buf &= entry.s
    buf &= '\n'
    if buf.len >= 4096:
      if not ps.writeDataLoop(buf):
        res = false
        break
      buf = ""
    if reverse:
      entry = entry.prev
    else:
      entry = entry.next
  if buf.len > 0 and not ps.writeDataLoop(buf):
    res = false
  if sync and res:
    res = fsync(ps.fd) == 0
  ps.sclose()
  return res

proc write*(hist: History; file: string): bool =
  let ps = newPosixStream(file)
  if ps != nil:
    var stats: Stat
    if fstat(ps.fd, stats) != -1 and S_ISREG(stats.st_mode):
      let mtime = int64(stats.st_mtime)
      if mtime > hist.mtime:
        hist.parse(ps, mtime)
      else:
        ps.sclose()
    else:
      ps.sclose()
  if hist.first == nil:
    return true
  block write:
    # Can't just use getTempFile, because the temp directory may be in
    # another filesystem.
    let tmp = file & '~'
    let ps = newPosixStream(tmp, O_WRONLY or O_CREAT, 0o600)
    if ps != nil and hist.write(ps, sync = true, reverse = false):
      return c_rename(cstring(tmp), file) == 0
  return false
