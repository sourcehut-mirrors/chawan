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

func newHistoryEntry(s: string): HistoryEntry =
  return HistoryEntry(s: s)

proc add(hist: History; entry: HistoryEntry) =
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

proc add*(hist: History; s: string) =
  hist.add(newHistoryEntry(s))

proc parse(hist: History; iq: openArray[char]) =
  var i = 0
  while i < iq.len:
    let entry = newHistoryEntry(iq.until('\n', i))
    hist.add(entry)
    i += entry.s.len + 1

# Consumes `ps'.
proc parse*(hist: History; ps: PosixStream; mtime: int64): bool =
  try:
    let src = ps.recvAllOrMmap()
    hist.parse(src.toOpenArray())
    hist.mtime = mtime
    deallocMem(src)
  except IOError:
    return false
  finally:
    ps.sclose()
  return true

proc c_rename(oldname, newname: cstring): cint {.importc: "rename",
  header: "<stdio.h>".}

# Consumes `ps'.
proc write*(hist: History; ps: PosixStream; reverse = false): bool =
  try:
    var buf = ""
    var entry = if reverse: hist.last else: hist.first
    while entry != nil:
      buf &= entry.s
      buf &= '\n'
      if buf.len >= 4096:
        ps.sendDataLoop(buf)
        buf = ""
      if reverse:
        entry = entry.prev
      else:
        entry = entry.next
    if buf.len > 0:
      ps.sendDataLoop(buf)
  except IOError:
    return false
  finally:
    ps.sclose()
  return true

proc write*(hist: History; file: string): bool =
  let ps = newPosixStream(file)
  if ps != nil:
    var stats: Stat
    if fstat(ps.fd, stats) != -1 and S_ISREG(stats.st_mode):
      let mtime = int64(stats.st_mtime)
      if mtime > hist.mtime:
        if not hist.parse(ps, mtime):
          return false
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
    if ps != nil and hist.write(ps):
      return c_rename(cstring(tmp), file) == 0
  return false
