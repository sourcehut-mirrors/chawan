# Generic object for line editing and browsing history.

{.push raises: [].}

import std/posix

import io/chafile
import io/dynstream
import utils/cowstr
import utils/opt
import utils/tabutil

type
  History* = ref object
    first*: HistoryEntry
    last*: HistoryEntry
    mtime*: int64
    map: StrMap
    maxLen: int
    transient*: bool # set if there is a failure in parsing history

  HistoryEntry* {.final.} = ref object of StrMapItem
    # For history entries, the entry is composed like
    #   url(\torigin)?
    #
    # Note: we cannot merge identical entries from separate origins because
    # taht would allow history enumeration attacks.  (Sketch: push an
    # entry known to be in history, an entry to check, then history-size
    # more fake entries.  If the entry to check is still in the history,
    # then the entry to check has been visited from another website,
    # otherwise it wasn't.)
    #TODO however, we could still merge the /representation/ by adding a
    # "weight" to each entry that counts how many origins it has been
    # accessed from.  When the entry gets shifted out, we just drop the
    # last origin (and if there are no more, the entry itself too).
    prev*: HistoryEntry
    next*: HistoryEntry

iterator items*(hist: History): HistoryEntry =
  var entry = hist.first
  while entry != nil:
    yield entry
    entry = entry.next

proc matchesEntryOrigin(s, origin: Str): bool =
  # Also make self-links visible, since the server already knows that the
  # user has visited anyway.
  let i = s.findOrLen(':')
  if not s.startsWith("://", i) or s.startsWith("file:///"):
    # Not a net_path, so only same-origin if url == origin.
    let j = s.findOrLen('\t')
    return s.toOpenArray(0, j - 1) == origin
  let j = s.findOrLen({'/', '\t'}, i + 3)
  return s.toOpenArray(0, j - 1) == origin

proc matchesOrigin(entry: HistoryEntry; origin: Str): bool =
  var i = entry.s.findOrLen('\t')
  if i < entry.s.len:
    return origin == entry.s.toOpenArray(i + 1, entry.s.high)
  matchesEntryOrigin(entry.s, origin)

iterator itemsOfOrigin*(hist: History; origin: Str): HistoryEntry =
  for entry in hist:
    if entry.matchesOrigin(origin):
      yield entry

proc getText*(entry: HistoryEntry): Str =
  percentDecode(entry.s.until('\t'))

proc shrink(hist: History) =
  # Provide a buffer of the history length so that merging in another
  # history doesn't just insert entries we've already shifted out.
  let maxLen = hist.maxLen * 2
  while hist.map.load > maxLen:
    hist.map.del(hist.first)
    if hist.first.next != nil:
      hist.first.next.prev = nil
    hist.first = hist.first.next
    if hist.first == nil:
      hist.last = nil

proc add(hist: History; entry: sink HistoryEntry; merge: bool) =
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
  if not merge:
    hist.shrink()

proc newHistory*(maxLen: int; mtime = 0i64): History =
  return History(maxLen: maxLen, mtime: mtime)

proc addRaw*(hist: History; s: sink Str; merge = false) =
  hist.add(HistoryEntry(s: s), merge)

proc addInput*(hist: History; s: Str) =
  # filter out tabulator
  hist.addRaw(percentEncode(s, ControlPercentEncodeSet))

proc addURL*(hist: History; s, origin: Str) =
  if origin == "" or matchesEntryOrigin(s, origin):
    # If origin is the same for the URL, it will be visible anyway.
    hist.addRaw(s)
  else:
    hist.addRaw(initStrM(s, '\t', origin))

proc contains*(hist: History; s: Str): bool =
  s.toOpenArray() in hist.map

proc len*(hist: History): int =
  hist.map.load

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
    var line = initGrowbuf()
    while ?file.readLine(line):
      hist.addRaw(move(line).toStr(), merge)
    hist.mtime = mtime
  ok()

# Consumes `ps'.
proc write*(hist: History; ps: PosixStream; sync, reverse: bool): Opt[void] =
  let file = ?ps.afdopen("w")
  if reverse:
    var entry = hist.last
    var i = 0
    while entry != nil:
      ?file.writeLine(entry.s.toOpenArray())
      entry = entry.prev
      inc i
      if i >= hist.maxLen:
        break # buffered entries follow
  else:
    var entry = hist.first
    for i in hist.maxLen ..< hist.map.load: # skip buffered entries
      if entry == nil:
        break
      entry = entry.next
    while entry != nil:
      ?file.writeLine(entry.s.toOpenArray())
      entry = entry.next
  ?file.flush()
  if sync and fsync(ps.fd) != 0:
    return err()
  ok()

proc write*(hist: History; file: Str): Opt[void] =
  let ps = newPosixStream(file.toCString())
  if ps != nil:
    ?hist.parse(ps, hist.mtime, merge = true)
    # delay shrink until merge is finished so that deduplication can work
    # correctly.  (otherwise, we'd get into a loop of shifting out the
    # last entry and then pushing it to the top with a full history)
    hist.shrink()
  if hist.first == nil:
    return ok()
  let tmp = initStrM(file, '~')
  discard unlink(tmp.toCString())
  let ps2 = newPosixStream(tmp.toCString(), O_WRONLY or O_CREAT or O_EXCL,
    0o600)
  if ps2 == nil:
    return err()
  ?hist.write(ps2, sync = true, reverse = false)
  ?chafile.rename(tmp, file)
  ok()

{.pop.} # raises: []
