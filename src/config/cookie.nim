{.push raises: [].}

import std/algorithm
import std/posix

import io/chafile
import io/dynstream
import io/packetreader
import io/packetwriter
import js/jsref
import js/jstypes
import server/url
import utils/chaos
import utils/cowstr
import utils/opt
import utils/tabutil
import utils/twtstr

type
  Cookie* {.final.} = ref object of StrMapItem
    name: Str
    value: Str
    expires: int64 # unix time
    domain: Str
    path: Str
    persist: bool
    secure: bool
    httpOnly: bool
    hostOnly: bool
    isnew: bool
    skip: bool

  CookieJar* {.final.} = ref object of StrMapItem
    cookies: seq[Cookie]
    map: StrMap # keyed on {host}{path}\t{name}
    next: CookieJar

  CookieJarMap* = ref object
    mtime: int64
    jars: StrMap
    jarsHead: CookieJar
    jarsTail: CookieJar
    transient*: bool # set if there is a failure in parsing cookies

  CookieKey = enum
    ckExpires = "expires"
    ckMaxAge = "max-age"
    ckSecure = "secure"
    ckHttponly = "httponly"
    ckPath = "path"
    ckDomain = "domain"

  Month = enum
    mJan = (1, "jan")
    mFeb = "feb"
    mMar = "mar"
    mApr = "apr"
    mMay = "may"
    mJun = "jun"
    mJul = "jul"
    mAug = "aug"
    mSep = "sep"
    mOct = "oct"
    mNov = "nov"
    mDec = "dec"

# Forward declarations
proc sread*(r: var PacketReader; cookieJar: var CookieJar): PacketCode =
  var n: bool
  ?r.sread(n)
  if n:
    cookieJar = CookieJar()
    ?r.sread(cookieJar.s)
    let len = ?r.readLen()
    cookieJar.cookies = newSeq[Cookie](len)
    for i in 0 ..< len:
      let cookie = Cookie()
      ?r.sread(cookie[])
      cookieJar.cookies[i] = cookie
      if not cookie.skip:
        cookieJar.map.put(cookie)
  else:
    cookieJar = nil
  ok()

proc swrite*(w: var PacketWriter; cookieJar: CookieJar) =
  w.swrite(cookieJar != nil)
  if cookieJar != nil:
    w.swrite(cookieJar.s)
    w.swrite(cookieJar.cookies.len)
    for cookie in cookieJar.cookies:
      w.swrite(cookie[])

proc newCookieJarMap*(): CookieJarMap =
  return CookieJarMap()

proc addNew*(map: CookieJarMap; name: Str): CookieJar =
  let jar = CookieJar(s: name)
  map.jars.put(jar)
  if map.jarsTail == nil:
    map.jarsHead = jar
  else:
    map.jarsTail.next = jar
  map.jarsTail = jar
  return jar

proc getOrDefault*(map: CookieJarMap; name: openArray[char]): CookieJar =
  return CookieJar(map.jars.getOrDefault(name))

proc getMapKey(cookie: Cookie): Str =
  initStrM(cookie.domain, cookie.path, "\t", cookie.name)

proc getDaysInMonth(month, year: int): int =
  if month == 2:
    if year mod 4 == 0 and (year mod 100 != 0 or year mod 400 == 0):
      return 29
    return 28
  if month == 4 or month == 6 or month == 9 or month == 11:
    return 30
  31

proc parseCookieDate*(val: openArray[char]): Opt[int64] =
  # cookie-date
  const Delimiters = {'\t', ' '..'/', ';'..'@', '['..'`', '{'..'~'}
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
        time[i] = parseInt32(timeField.toOpenArray()).get
        inc i
      if i == 3:
        foundTime = true
        continue
    if dayOfMonth == 0: # test for day-of-month
      let digits = dateToken.until(NonDigit)
      if digits.len in 1..2:
        dayOfMonth = parseInt32(digits.toOpenArray()).get
        continue
    if month == 0: # test for month
      if dateToken.len >= 3:
        if x := parseEnumNoCase[Month](dateToken.toOpenArray(0, 2)):
          month = int(x)
          continue
    if year == -1: # test for year
      let digits = dateToken.until(NonDigit)
      if digits.len == 4:
        year = parseInt32(digits.toOpenArray()).get
        continue
  if month == 0 or dayOfMonth notin 1..getDaysInMonth(month, year) or
      year < 1601 or not foundTime or
      time[0] > 23 or time[1] > 59 or time[2] > 59:
    return err()
  if year < 1970:
    return ok(0)
  # https://howardhinnant.github.io/date_algorithms.html
  if month <= 2:
    dec year
  let era = (if year >= 0: year else: year - 399) div 400
  let yoe = year - era * 400
  let doy = (153 * (if month > 2: month - 3 else: month + 9) + 2) div 5 +
    dayOfMonth - 1
  let doe = yoe * 365 + yoe div 4 - yoe div 100 + doy
  let day = era * 146097 + doe - 719468
  ok(day * 24 * 60 * 60 + time[0] * 60 * 60 + time[1] * 60 + time[2])

# https://www.rfc-editor.org/rfc/rfc6265#section-5.1.4
proc defaultCookiePath(url: URL): Str =
  var path = url.pathname.untilLast('/')
  if path.len <= 0 or path[0] != '/':
    return str("/")
  move(path)

proc cookiePathMatches(cookiePath, requestPath: Str): bool =
  if requestPath.startsWith(cookiePath):
    if requestPath.len == cookiePath.len:
      return true
    if cookiePath[^1] == '/':
      return true
    if requestPath.len > cookiePath.len and requestPath[cookiePath.len] == '/':
      return true
  return false

proc cookieDomainMatches(cookieDomain: Str; url: URL): bool =
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
  cookie.s = cookie.getMapKey()
  let old = Cookie(cookieJar.map.getOrDefault(cookie.s))
  if old != nil:
    if parseMode and old.isnew:
      return # do not override newly added cookies
    if persist or not old.persist:
      let i = cookieJar.cookies.find(old)
      cookieJar.cookies.delete(i)
    else:
      # we cannot save this cookie, but it must be kept for this session.
      old.skip = true
  cookieJar.map.put(cookie)
  cookieJar.cookies.add(cookie)

# https://www.rfc-editor.org/rfc/rfc6265#section-5.4
# if http is true, httpOnly cookies are included too
proc serialize*(cookieJar: CookieJar; url: URL; http: bool): Str =
  var buf = initGrowbuf()
  let t = getUnixSeconds()
  var expired: seq[int] = @[]
  for i, cookie in cookieJar.cookies.mypairs:
    let cookie = cookieJar.cookies[i]
    if cookie.skip: # "read-only" cookie
      continue
    if cookie.expires != -1 and cookie.expires <= t:
      expired.add(i)
      continue
    if not http and cookie.httpOnly:
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
    if buf != "":
      buf &= "; "
    buf.addM(cookie.name, '=', cookie.value)
  for i in expired.ritems:
    cookieJar.map.del(cookieJar.cookies[i])
    cookieJar.cookies.delete(i)
  buf.toStr()

proc parseSetCookie(str: Str; t: int64; url: URL; persist, http: bool):
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
        # Gecko seems to accept such cookies, but Blink drops them too,
        # so this should be safe from a compat perspective.
        return err()
      cookie.name = part.until('=')
      cookie.value = part.substr(cookie.name.len + 1)
      first = false
      continue
    let part = part.strip(leading = true, trailing = false)
    let i = part.findOrLen('=')
    let key = parseEnumNoCase[CookieKey](part.toOpenArray(0, i - 1))
    if key.isErr:
      continue
    let valStart = min(i + 1, part.len)
    case key.get
    of ckExpires:
      if cookie.expires == -1:
        if date := parseCookieDate(part.toOpenArray(valStart, part.high)):
          cookie.expires = date
    of ckMaxAge:
      let x = parseInt32(part.toOpenArray(valStart, part.high)).get(-1)
      if x >= 0:
        cookie.expires = t + x
    of ckSecure: cookie.secure = true
    of ckHttponly:
      if not http:
        return err()
      cookie.httpOnly = true
    of ckPath:
      let val = part.substr(valStart)
      if val != "" and val[0] == '/' and '\t' notin val:
        hasPath = true
        cookie.path = val
    of ckDomain:
      if valStart >= part.len:
        continue # "Domain=" has no effect
      let val = part.substr(valStart)
      var hostType = htNone
      var domain = parseHost(val, url.schemeType, hostType)
      if domain.len > 0 and domain[0] == '.':
        domain.delete(0..0)
      if hostType == htNone or not cookieDomainMatches(domain, url):
        return err()
      if hostType != htNone:
        cookie.domain = domain
        cookie.hostOnly = false
  if cookie.hostOnly:
    cookie.domain = url.hostname
  if not hasPath:
    cookie.path = defaultCookiePath(url)
  if cookie.expires < 0:
    cookie.persist = false
  return ok(cookie)

proc setCookie*(cookieJar: CookieJar; header: openArray[ByteString]; url: URL;
    persist, http: bool) =
  let t = getUnixSeconds()
  var sorted = true
  for s in header:
    if cookie := parseSetCookie(s.toStr(), t, url, persist, http):
      cookieJar.add(cookie, persist = persist)
      sorted = false
  if not sorted:
    cookieJar.cookies.sort(proc(a, b: Cookie): int =
      return cmp(a.path.len, b.path.len), order = Descending)

type ParseState = object
  i: int
  error: bool

proc nextField(state: var ParseState; iq: Growbuf): Str =
  if state.i >= iq.len:
    state.error = true
    return str("")
  let i = iq.findOrLen('\t', state.i)
  let s = initStr(iq.toOpenArray(state.i, i - 1))
  state.i = min(i + 1, iq.len)
  s

proc nextBool(state: var ParseState; iq: Growbuf): bool =
  let field = state.nextField(iq)
  if field == "TRUE":
    return true
  if field != "FALSE":
    state.error = true
  return false

proc nextInt64(state: var ParseState; iq: Growbuf): int64 =
  if x := parseInt64(state.nextField(iq).toOpenArray()):
    return x
  state.error = true
  return 0

proc parse0(map: CookieJarMap; file: AChaFile; warnings: var seq[Str]): Opt[void] =
  var line = initGrowbuf()
  var nline = 0
  while ?file.readLine(line):
    if line.len != 0:
      var state = ParseState()
      var httpOnly = false
      if line[0] == '#':
        if not line.toOpenArray().startsWith("HttpOnly_", 1):
          inc nline
          continue
        state.i += "#HttpOnly_".len
        httpOnly = true
      state.error = false
      let cookie = Cookie(httpOnly: httpOnly, persist: true)
      var domain = state.nextField(line)
      var cookieJar: CookieJar = nil
      if (let j = domain.find('@'); j >= 0):
        cookie.domain = domain.substr(j + 1)
        if cookie.domain.startsWith("."):
          cookie.domain.delete(0..0)
        domain.setLen(j)
      else:
        if domain[0] == '.':
          domain.delete(0..0)
        cookie.domain = domain
      cookieJar = map.getOrDefault(domain.toOpenArray())
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
        warnings.add(initStrM("skipped invalid cookie line ", nline))
    inc nline
  ok()

# Consumes `ps'.
# If the cookie file's mtime is less than otime, it won't be parsed.
# (This is used when writing the file, to merge in new data
# from other instances written after we first parsed the file.)
proc parse*(map: CookieJarMap; ps: PosixStream; warnings: var seq[Str];
    otime = int64.high): Opt[void] =
  var stats: Stat
  if fstat(ps.fd, stats) == -1:
    ps.sclose()
    return err()
  let mtime = int64(stats.st_mtime)
  if mtime < otime:
    let file = ?ps.afdopen("r")
    ?map.parse0(file, warnings)
    map.mtime = mtime
  ok()

proc write0(map: CookieJarMap; file: AChaFile; ps: PosixStream;
    tmp, path: Str): Opt[void] =
  ?file.write("""
# Netscape HTTP Cookie file
# Autogenerated by Chawan.  Manually added cookies are normally
# preserved, but comments will be lost.

""")
  var i = 0
  let time = getUnixSeconds()
  var buf = initGrowbuf()
  var jar = map.jarsHead
  while jar != nil:
    for cookie in jar.cookies:
      if cookie.expires <= time or not cookie.persist:
        continue # session cookie
      if cookie.httpOnly:
        buf &= "#HttpOnly_"
      if cookie.domain != jar.s:
        buf.addM(jar.s, '@')
      if not cookie.hostOnly:
        buf &= '.'
      buf.addM(cookie.domain, '\t')
      const BoolMap = [false: str("FALSE"), true: str("TRUE")]
      buf.addM(BoolMap[not cookie.hostOnly], '\t', # flipped intentionally
        cookie.path, '\t',
        BoolMap[cookie.secure], '\t', cookie.expires, '\t')
      buf.addM(cookie.name, '\t', cookie.value, '\n')
      ?file.write(buf.toOpenArray())
      buf.setLen(0)
      inc i
    jar = jar.next
  if i == 0:
    discard unlink(tmp.toCString())
    discard unlink(path.toCString())
    return ok()
  if fsync(ps.fd) != 0:
    return err()
  return chafile.rename(tmp, path)

proc write*(map: CookieJarMap; path: Str): Opt[void] =
  let ps = newPosixStream(path)
  if ps != nil:
    var dummy: seq[Str]
    ?map.parse(ps, dummy, map.mtime)
  elif map.jarsHead == nil:
    return ok()
  let tmp = initStrM(path, '~')
  discard unlink(tmp.toCString())
  let ps2 = newPosixStream(tmp, O_WRONLY or O_CREAT or O_EXCL, 0o600)
  if ps2 == nil:
    return err()
  let file = ?ps2.afdopen("w")
  ?map.write0(file, ps2, tmp, path)
  ok()

proc needsWrite*(map: CookieJarMap): bool =
  not map.transient and map.jarsHead != nil

{.pop.} # raises: []
