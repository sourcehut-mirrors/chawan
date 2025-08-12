{.push raises: [].}

import std/algorithm
import std/posix
import std/strutils
import std/tables
import std/times

import io/chafile
import io/dynstream
import io/packetreader
import io/packetwriter
import types/opt
import types/url
import utils/twtstr

type
  Cookie* = ref object
    name: string
    value: string
    expires: int64 # unix time
    domain: string
    path: string
    persist: bool
    secure: bool
    httpOnly: bool
    hostOnly: bool
    isnew: bool
    skip: bool

  CookieJar* = ref object
    name*: string
    cookies: seq[Cookie]
    map: Table[string, Cookie] # {host}{path}\t{name}

  CookieJarMap* = ref object
    mtime: int64
    jars: OrderedTable[cstring, CookieJar]
    transient*: bool # set if there is a failure in parsing cookies

# Forward declarations
proc getMapKey(cookie: Cookie): string

proc sread*(r: var PacketReader; cookieJar: var CookieJar) =
  var n: bool
  r.sread(n)
  if n:
    cookieJar = CookieJar()
    r.sread(cookieJar.name)
    r.sread(cookieJar.cookies)
    for cookie in cookieJar.cookies:
      if not cookie.skip:
        cookieJar.map[cookie.getMapKey()] = cookie
  else:
    cookieJar = nil

proc swrite*(w: var PacketWriter; cookieJar: CookieJar) =
  w.swrite(cookieJar != nil)
  if cookieJar != nil:
    w.swrite(cookieJar.name)
    w.swrite(cookieJar.cookies)

proc newCookieJarMap*(): CookieJarMap =
  return CookieJarMap()

proc addNew*(map: CookieJarMap; name: sink string): CookieJar =
  let jar = CookieJar(name: name)
  map.jars[cstring(jar.name)] = jar
  return jar

proc getOrDefault*(map: CookieJarMap; name: string): CookieJar =
  return map.jars.getOrDefault(cstring(name))

proc getMapKey(cookie: Cookie): string =
  return cookie.domain & cookie.path & '\t' & cookie.name

proc parseCookieDate(val: string): Opt[int64] =
  # cookie-date
  const Delimiters = {'\t', ' '..'/', ';'..'@', '['..'`', '{'..'~'}
  const NonDigit = AllChars - AsciiDigit
  var foundTime = false
  # date-token-list
  var time = array[3, int].default
  var dayOfMonth = 0
  var month = 0
  var year = -1
  for dateToken in val.split(Delimiters):
    if dateToken == "": continue # *delimiter
    if not foundTime: # test for time
      let hmsTime = dateToken.until(NonDigit - {':'})
      var i = 0
      for timeField in hmsTime.split(':'):
        if i > 2:
          i = 0
          break # too many time fields
        # 1*2DIGIT
        if timeField.len != 1 and timeField.len != 2:
          i = 0
          break
        time[i] = parseInt32(timeField).get
        inc i
      if i == 3:
        foundTime = true
        continue
    if dayOfMonth == 0: # test for day-of-month
      let digits = dateToken.until(NonDigit)
      if digits.len in 1..2:
        dayOfMonth = parseInt32(digits).get
        continue
    if month == 0: # test for month
      if dateToken.len >= 3:
        case dateToken.substr(0, 2).toLowerAscii()
        of "jan": month = 1
        of "feb": month = 2
        of "mar": month = 3
        of "apr": month = 4
        of "may": month = 5
        of "jun": month = 6
        of "jul": month = 7
        of "aug": month = 8
        of "sep": month = 9
        of "oct": month = 10
        of "nov": month = 11
        of "dec": month = 12
        else: discard
        if month != 0:
          continue
    if year == -1: # test for year
      let digits = dateToken.until(NonDigit)
      if digits.len == 4:
        year = parseInt32(digits).get
        continue
  if month == 0 or dayOfMonth notin 1..getDaysInMonth(Month(month), year) or
      year < 1601 or not foundTime or
      time[0] > 23 or time[1] > 59 or time[2] > 59:
    return err()
  let dt = dateTime(year, Month(month), MonthdayRange(dayOfMonth),
    HourRange(time[0]), MinuteRange(time[1]), SecondRange(time[2]),
    zone = utc())
  ok(dt.toTime().toUnix())

# For debugging
proc `$`*(cookieJar: CookieJar): string =
  result = ""
  for cookie in cookieJar.cookies:
    result &= "Cookie "
    result &= $cookie[]
    result &= "\n"

# https://www.rfc-editor.org/rfc/rfc6265#section-5.1.4
func defaultCookiePath(url: URL): string =
  var path = url.pathname.untilLast('/')
  if path == "" or path[0] != '/':
    return "/"
  move(path)

func cookiePathMatches(cookiePath, requestPath: string): bool =
  if requestPath.startsWith(cookiePath):
    if requestPath.len == cookiePath.len:
      return true
    if cookiePath[^1] == '/':
      return true
    if requestPath.len > cookiePath.len and requestPath[cookiePath.len] == '/':
      return true
  return false

func cookieDomainMatches(cookieDomain: string; url: URL): bool =
  if cookieDomain.len == 0:
    return false
  if url.isIP():
    return url.hostname == cookieDomain
  if url.hostname.endsWith(cookieDomain) and
      url.hostname.len >= cookieDomain.len:
    return url.hostname.len == cookieDomain.len or
      url.hostname[url.hostname.len - cookieDomain.len - 1] == '.'
  return false

proc add(cookieJar: CookieJar; cookie: Cookie; parseMode = false,
    persist = true) =
  let s = cookie.getMapKey()
  let old = cookieJar.map.getOrDefault(s)
  if old != nil:
    if parseMode and old.isnew:
      return # do not override newly added cookies
    if persist or not old.persist:
      let i = cookieJar.cookies.find(old)
      cookieJar.cookies.delete(i)
    else:
      # we cannot save this cookie, but it must be kept for this session.
      old.skip = true
  cookieJar.map[s] = cookie
  cookieJar.cookies.add(cookie)

# https://www.rfc-editor.org/rfc/rfc6265#section-5.4
proc serialize*(cookieJar: CookieJar; url: URL): string =
  var res = ""
  let t = getTime().toUnix()
  var expired: seq[int] = @[]
  for i, cookie in cookieJar.cookies.mypairs:
    let cookie = cookieJar.cookies[i]
    if cookie.skip: # "read-only" cookie
      continue
    if cookie.expires != -1 and cookie.expires <= t:
      expired.add(i)
      continue
    if cookie.secure and url.schemeType != stHttps and
        url.hostname != "localhost":
      continue
    if not cookiePathMatches(cookie.path, url.pathname):
      continue
    if cookie.hostOnly and cookie.domain != url.hostname:
      continue
    if not cookie.hostOnly and not cookieDomainMatches(cookie.domain, url):
      continue
    if res != "":
      res &= "; "
    res &= cookie.name
    res &= "="
    res &= cookie.value
  for j in countdown(expired.high, 0):
    let i = expired[j]
    cookieJar.map.del(cookieJar.cookies[i].getMapKey())
    cookieJar.cookies.delete(i)
  move(res)

proc parseSetCookie(str: string; t: int64; url: URL; persist: bool):
    Opt[Cookie] =
  let cookie = Cookie(
    expires: -1,
    hostOnly: true,
    persist: persist,
    isnew: true
  )
  var first = true
  var hasPath = false
  for part in str.split(';'):
    if first:
      if '\t' in part:
        # Drop cookie if it has a tab.
        # Gecko seems to accept it, but Blink drops it too,
        # so this should be safe from a compat perspective.
        continue
      cookie.name = part.until('=')
      cookie.value = part.substr(cookie.name.len + 1)
      first = false
      continue
    let part = part.strip(leading = true, trailing = false, AsciiWhitespace)
    let key = part.untilLower('=')
    let val = part.substr(key.len + 1)
    case key
    of "expires":
      if cookie.expires == -1:
        if date := parseCookieDate(val):
          cookie.expires = date
    of "max-age":
      let x = parseInt32(val).get(-1)
      if x >= 0:
        cookie.expires = t + x
    of "secure": cookie.secure = true
    of "httponly": cookie.httpOnly = true
    of "path":
      if val != "" and val[0] == '/' and '\t' notin val:
        hasPath = true
        cookie.path = val
    of "domain":
      var hostType = htNone
      var domain = parseHost(val, special = false, hostType)
      if domain.len > 0 and domain[0] == '.':
        domain.delete(0..0)
      if hostType == htNone or not cookieDomainMatches(domain, url):
        return err()
      if hostType != htNone:
        cookie.domain = move(domain)
        cookie.hostOnly = false
  if cookie.hostOnly:
    cookie.domain = url.hostname
  if not hasPath:
    cookie.path = defaultCookiePath(url)
  if cookie.expires < 0:
    cookie.persist = false
  return ok(cookie)

proc setCookie*(cookieJar: CookieJar; header: openArray[string]; url: URL;
    persist: bool) =
  let t = getTime().toUnix()
  var sorted = true
  for s in header:
    if cookie := parseSetCookie(s, t, url, persist):
      cookieJar.add(cookie, persist = persist)
      sorted = false
  if not sorted:
    cookieJar.cookies.sort(proc(a, b: Cookie): int =
      return cmp(a.path.len, b.path.len), order = Descending)

type ParseState = object
  i: int
  error: bool

proc nextField(state: var ParseState; iq: openArray[char]): string =
  if state.i >= iq.len:
    state.error = true
    return ""
  var field = iq.until('\t', state.i)
  state.i += field.len
  if state.i < iq.len and iq[state.i] == '\t':
    inc state.i
  move(field)

proc nextBool(state: var ParseState; iq: openArray[char]): bool =
  let field = state.nextField(iq)
  if field == "TRUE":
    return true
  if field != "FALSE":
    state.error = true
  return false

proc nextInt64(state: var ParseState; iq: openArray[char]): int64 =
  if x := parseInt64(state.nextField(iq)):
    return x
  state.error = true
  return 0

proc parse0(map: CookieJarMap; file: ChaFile; warnings: var seq[string]):
    Opt[void] =
  var line = ""
  var nline = 0
  while ?file.readLine(line):
    if line.len != 0:
      var state = ParseState()
      var httpOnly = false
      if line[0] == '#':
        inc state.i
        let first = line.until('_', state.i)
        state.i += first.len
        if first != "HttpOnly":
          inc nline
          continue
        inc state.i
        httpOnly = true
      state.error = false
      let cookie = Cookie(httpOnly: httpOnly, persist: true)
      var domain = state.nextField(line)
      var cookieJar: CookieJar = nil
      if (let j = domain.find('@'); j != -1):
        cookie.domain = domain.substr(j + 1)
        if cookie.domain[0] == '.':
          cookie.domain.delete(0..0)
        domain.setLen(j)
      else:
        if domain[0] == '.':
          domain.delete(0..0)
        cookie.domain = domain
      cookieJar = map.getOrDefault(domain)
      if cookieJar == nil:
        cookieJar = map.addNew(domain)
      cookie.hostOnly = not state.nextBool(line)
      cookie.path = state.nextField(line)
      cookie.secure = state.nextBool(line)
      cookie.expires = state.nextInt64(line)
      cookie.name = state.nextField(line)
      cookie.value = state.nextField(line)
      if not state.error:
        cookieJar.add(cookie, parseMode = true)
      else:
        warnings.add("skipped invalid cookie line " & $nline)
    inc nline
  ok()

# Consumes `ps'.
# If the cookie file's mtime is less than otime, it won't be parsed.
# (This is used when writing the file, to merge in new data
# from other instances written after we first parsed the file.)
proc parse*(map: CookieJarMap; ps: PosixStream; warnings: var seq[string];
    otime = int64.high): Opt[void] =
  var stats: Stat
  if fstat(ps.fd, stats) == -1:
    ps.sclose()
    return err()
  let mtime = int64(stats.st_mtime)
  if mtime < otime:
    let file = ?ps.fdopen("r")
    let res = map.parse0(file, warnings)
    ?file.close()
    ?res
    map.mtime = mtime
  ok()

proc write0(map: CookieJarMap; file: ChaFile; ps: PosixStream;
    tmp, path: string): Opt[void] =
  ?file.write("""
# Netscape HTTP Cookie file
# Autogenerated by Chawan.  Manually added cookies are normally
# preserved, but comments will be lost.

""")
  var i = 0
  let time = getTime().toUnix()
  for name, jar in map.jars:
    for cookie in jar.cookies:
      if cookie.expires <= time or not cookie.persist:
        continue # session cookie
      var buf = ""
      if cookie.httpOnly:
        buf &= "#HttpOnly_"
      if cstring(cookie.domain) != name:
        buf &= $name & "@"
      if not cookie.hostOnly:
        buf &= '.'
      buf &= cookie.domain & '\t'
      const BoolMap = [false: "FALSE", true: "TRUE"]
      buf &= BoolMap[not cookie.hostOnly] & '\t' # flipped intentionally
      buf &= cookie.path & '\t'
      buf &= BoolMap[cookie.secure] & '\t'
      buf &= $cookie.expires & '\t'
      buf &= cookie.name & '\t'
      buf &= cookie.value & '\n'
      ?file.write(buf)
      inc i
  if i == 0:
    discard unlink(cstring(tmp))
    discard unlink(cstring(path))
    return ok()
  if fsync(ps.fd) != 0:
    return err()
  return chafile.rename(tmp, path)

proc write*(map: CookieJarMap; path: string): Opt[void] =
  let ps = newPosixStream(path)
  if ps != nil:
    var dummy: seq[string] = @[]
    ?map.parse(ps, dummy, map.mtime)
  elif map.jars.len == 0:
    return ok()
  let tmp = path & '~'
  let ps2 = newPosixStream(tmp, O_WRONLY or O_CREAT, 0o600)
  if ps2 == nil:
    return err()
  let file = ?ps2.fdopen("w")
  let res = map.write0(file, ps2, tmp, path)
  ?file.close()
  res

{.pop.} # raises: []
