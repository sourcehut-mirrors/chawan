# Generic object for line editing and browsing hist.

{.push raises: [].}

import std/posix
import utils/tabutil

import io/chafile
import io/dynstream
import types/opt

type
  History* = ref object
    first*: HistoryEntry
    last*: HistoryEntry
    mtime*: int64
    map: StrMap
    maxLen: int
    transient*: bool # set if there is a failure in parsing history

  HistoryEntry* {.final.} = ref object of StrMapItem
    prev*: HistoryEntry
    next*: HistoryEntry

proc add(hist: History; entry: sink HistoryEntry; merge = false) =
  let old = HistoryEntry(hist.map.getOrDefault(entry.s))
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
  if hist.first == nil:
    hist.first = entry
  else:
    entry.prev = hist.last
    hist.last.next = entry
  hist.map.put(entry)
  hist.last = entry
  if hist.map.load > hist.maxLen:
    hist.map.del(hist.first)
    if hist.first.next != nil:
      hist.first.next.prev = nil
    hist.first = hist.first.next
    if hist.first == nil:
      hist.last = nil

proc newHistory*(maxLen: int; mtime = 0i64): History =
  return History(maxLen: maxLen, mtime: mtime)

proc add*(hist: History; s: sink string) =
  hist.add(HistoryEntry(s: s), merge = false)

proc clear*(hist: History) =
  var it = move(hist.first)
  hist.last = nil
  while it != nil:
    let next = move(it.next)
    it.prev = nil
    it = next

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
    let file = ?ps.afdopen("r")
    var line = ""
    while ?file.readLine(line):
      hist.add(HistoryEntry(s: move(line)), merge)
    hist.mtime = mtime
  ok()

# Consumes `ps'.
proc write*(hist: History; ps: PosixStream; sync, reverse: bool): Opt[void] =
  let file = ?ps.afdopen("w")
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
  if sync and fsync(ps.fd) != 0:
    return err()
  ok()

proc write*(hist: History; file: string): Opt[void] =
  let ps = newPosixStream(file)
  if ps != nil:
    ?hist.parse(ps, hist.mtime, merge = true)
  if hist.first == nil:
    return ok()
  let tmp = file & '~'
  discard unlink(cstring(tmp))
  let ps2 = newPosixStream(tmp, O_WRONLY or O_CREAT or O_EXCL, 0o600)
  if ps2 == nil:
    return err()
  ?hist.write(ps2, sync = true, reverse = false)
  ?chafile.rename(tmp, file)
  ok()

{.pop.} # raises: []
