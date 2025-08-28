# Generic object for line editing and browsing hist.

{.push raises: [].}

import std/posix
import std/tables

import io/chafile
import io/dynstream
import types/opt

type
  History* = ref object
    first*: HistoryEntry
    last*: HistoryEntry
    mtime*: int64
    map: Table[string, HistoryEntry]
    len: int
    maxLen: int
    transient*: bool # set if there is a failure in parsing history

  HistoryEntry* = ref object
    s*: string
    prev* {.cursor.}: HistoryEntry
    next*: HistoryEntry

proc add(hist: History; entry: sink HistoryEntry; merge = false) =
  let old = hist.map.getOrDefault(entry.s)
  if merge and old != nil:
    return
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

proc newHistory*(maxLen: int; mtime = 0i64): History =
  return History(maxLen: maxLen, mtime: mtime)

proc add*(hist: History; s: sink string) =
  hist.add(HistoryEntry(s: s), merge = false)

proc parse0(hist: History; file: ChaFile; merge: bool): Opt[void] =
  var line = ""
  while ?file.readLine(line):
    hist.add(HistoryEntry(s: move(line)), merge)
  ok()

# Consumes `ps'.
# If the history file's mtime is less than otime, it won't be parsed.
# (This is used when writing the file, to merge in new data from other
# instances written after we first parsed the file.)
proc parse*(hist: History; ps: PosixStream; otime = int64.low;
    merge = false): Opt[void] =
  var stats: Stat
  if fstat(ps.fd, stats) == -1:
    ps.sclose()
    return err()
  let mtime = int64(stats.st_mtime)
  if otime < mtime:
    let file = ?ps.fdopen("r")
    let res = hist.parse0(file, merge)
    ?file.close()
    ?res
    hist.mtime = mtime
  ok()

proc write0(hist: History; file: ChaFile; reverse: bool): Opt[void] =
  if reverse:
    var entry = hist.last
    while entry != nil:
      ?file.writeLine(entry.s)
      entry = entry.prev
  else:
    var entry = hist.first
    while entry != nil:
      ?file.writeLine(entry.s)
      entry = entry.next
  ?file.flush()
  ok()

# Consumes `ps'.
proc write*(hist: History; ps: PosixStream; sync, reverse: bool): Opt[void] =
  let file = ?ps.fdopen("w")
  var res = hist.write0(file, reverse)
  if res.isOk and sync and fsync(ps.fd) != 0:
    res = err()
  ?file.close()
  res

proc write*(hist: History; file: string): Opt[void] =
  let ps = newPosixStream(file)
  if ps != nil:
    ?hist.parse(ps, hist.mtime, merge = true)
  if hist.first == nil:
    return ok()
  let tmp = file & '~'
  let ps2 = newPosixStream(tmp, O_WRONLY or O_CREAT, 0o600)
  if ps2 == nil:
    return err()
  ?hist.write(ps2, sync = true, reverse = false)
  ?chafile.rename(tmp, file)
  ok()

{.pop.} # raises: []
