import std/options
import std/strutils
import std/times

import monoucha/jsregex
import types/opt
import types/url
import utils/twtstr

type
  Cookie* = ref object
    name: string
    value: string
    expires: int64 # unix time
    secure: bool
    httponly: bool
    hostOnly: bool
    domain: string
    path: string

  CookieJar* = ref object
    domain: string
    allowHosts: seq[Regex]
    cookies*: seq[Cookie]

proc parseCookieDate(val: string): Option[int64] =
  # cookie-date
  const Delimiters = {'\t', ' '..'/', ';'..'@', '['..'`', '{'..'~'}
  const NonDigit = AllChars - AsciiDigit
  var foundTime = false
  var foundDayOfMonth = false
  var foundMonth = false
  var foundYear = false
  # date-token-list
  var time = array[3, int].default
  var dayOfMonth = 0
  var month = 0
  var year = 0
  for dateToken in val.split(Delimiters):
    if dateToken == "": continue # *delimiter
    if not foundTime:
      block timeBlock: # test for time
        let hmsTime = dateToken.until(NonDigit - {':'})
        var i = 0
        for timeField in hmsTime.split(':'):
          if i > 2: break timeBlock # too many time fields
          # 1*2DIGIT
          if timeField.len != 1 and timeField.len != 2: break timeBlock
          var timeFields = array[3, int].default
          for c in timeField:
            if c notin AsciiDigit: break timeBlock
            timeFields[i] *= 10
            timeFields[i] += c.decValue
          time = timeFields
          inc i
        if i != 3: break timeBlock
        foundTime = true
        continue
    if not foundDayOfMonth:
      block dayOfMonthBlock: # test for day-of-month
        let digits = dateToken.until(NonDigit)
        if digits.len != 1 and digits.len != 2: break dayOfMonthBlock
        var n = 0
        for c in digits:
          if c notin AsciiDigit: break dayOfMonthBlock
          n *= 10
          n += c.decValue
        dayOfMonth = n
        foundDayOfMonth = true
        continue
    if not foundMonth:
      block monthBlock: # test for month
        if dateToken.len < 3: break monthBlock
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
        else: break monthBlock
        foundMonth = true
        continue
    if not foundYear:
      block yearBlock: # test for year
        let digits = dateToken.until(NonDigit)
        if digits.len != 2 and digits.len != 4: break yearBlock
        var n = 0
        for c in digits:
          if c notin AsciiDigit: break yearBlock
          n *= 10
          n += c.decValue
        year = n
        foundYear = true
        continue
  if not (foundDayOfMonth and foundMonth and foundYear and foundTime):
    return none(int64)
  if dayOfMonth notin 0..31: return none(int64)
  if year < 1601: return none(int64)
  if time[0] > 23: return none(int64)
  if time[1] > 59: return none(int64)
  if time[2] > 59: return none(int64)
  let dt = dateTime(year, Month(month), MonthdayRange(dayOfMonth),
    HourRange(time[0]), MinuteRange(time[1]), SecondRange(time[2]))
  return some(dt.toTime().toUnix())

# For debugging
proc `$`*(cookieJar: CookieJar): string =
  result &= $cookieJar.domain
  result &= ":\n"
  for re in cookieJar.allowHosts:
    result &= "third-party " & $re & '\n'
  for cookie in cookieJar.cookies:
    result &= "Cookie "
    result &= $cookie[]
    result &= "\n"

# https://www.rfc-editor.org/rfc/rfc6265#section-5.1.4
func defaultCookiePath(url: URL): string =
  let path = url.pathname.untilLast('/')
  if path == "" or path[0] != '/':
    return "/"
  return path

func cookiePathMatches(cookiePath, requestPath: string): bool =
  if requestPath.startsWith(cookiePath):
    if requestPath.len == cookiePath.len:
      return true
    if cookiePath[^1] == '/':
      return true
    if requestPath.len > cookiePath.len and requestPath[cookiePath.len] == '/':
      return true
  return false

# I have no clue if this is actually compliant, because the spec is worded
# so badly.
# Either way, this implementation is needed for compatibility.
# (Here is this part of the spec in its full glory:
#   A string domain-matches a given domain string if at least one of the
#   following conditions hold:
#   o  The domain string and the string are identical.  (Note that both
#      the domain string and the string will have been canonicalized to
#      lower case at this point.)
#   o  All of the following conditions hold:
#      *  The domain string is a suffix of the string.
#      *  The last character of the string that is not included in the
#         domain string is a %x2E (".") character. (???)
#      *  The string is a host name (i.e., not an IP address).)
func cookieDomainMatches(cookieDomain: string; url: URL): bool =
  if cookieDomain.len == 0:
    return false
  let host = url.host
  if host == cookieDomain:
    return true
  if url.isIP():
    return false
  let cookieDomain = if cookieDomain[0] == '.':
    cookieDomain.substr(1)
  else:
    cookieDomain
  return host.endsWith(cookieDomain)

proc add(cookieJar: CookieJar; cookie: Cookie) =
  var i = -1
  for j, old in cookieJar.cookies.mypairs:
    if old.name == cookie.name and old.domain == cookie.domain and
        old.path == cookie.path:
      i = j
      break
  if i != -1:
    cookieJar.cookies[i] = cookie
  else:
    cookieJar.cookies.add(cookie)

proc match(cookieJar: CookieJar; url: URL): bool =
  if cookieJar.domain.cookieDomainMatches(url):
    return true
  if cookieJar.allowHosts.len > 0:
    let host = url.host
    for re in cookieJar.allowHosts:
      if re.match(host):
        return true
  return false

# https://www.rfc-editor.org/rfc/rfc6265#section-5.4
proc serialize*(cookieJar: CookieJar; url: URL): string =
  if not cookieJar.match(url):
    return ""
  var res = ""
  let t = getTime().toUnix()
  #TODO sort
  for i in countdown(cookieJar.cookies.high, 0):
    let cookie = cookieJar.cookies[i]
    if cookie.expires != -1 and cookie.expires <= t:
      cookieJar.cookies.delete(i)
      continue
    if cookie.secure and url.scheme != "https":
      continue
    if not cookiePathMatches(cookie.path, url.pathname):
      continue
    if cookie.hostOnly and cookie.domain != url.host:
      continue
    if not cookie.hostOnly and not cookieDomainMatches(cookie.domain, url):
      continue
    if res != "":
      res &= "; "
    res &= cookie.name
    res &= "="
    res &= cookie.value
  return res

proc parseCookie(str: string; t: int64; url: URL): Opt[Cookie] =
  let cookie = Cookie(expires: -1, hostOnly: true)
  var first = true
  var hasPath = false
  for part in str.split(';'):
    if first:
      cookie.name = part.until('=')
      cookie.value = part.after('=')
      first = false
      continue
    let part = part.strip(leading = true, trailing = false, AsciiWhitespace)
    let n = part.find('=')
    if n <= 0:
      continue
    let key = part.substr(0, n - 1)
    let val = part.substr(n + 1)
    case key.toLowerAscii()
    of "expires":
      if cookie.expires == -1:
        let date = parseCookieDate(val)
        if date.isSome:
          cookie.expires = date.get
    of "max-age":
      let x = parseInt64(val)
      if x.isSome:
        cookie.expires = t + x.get
    of "secure": cookie.secure = true
    of "httponly": cookie.httponly = true
    of "path":
      if val != "" and val[0] == '/':
        hasPath = true
        cookie.path = val
    of "domain":
      if not cookieDomainMatches(val, url):
        return err()
      cookie.domain = val
      cookie.hostOnly = true
  if cookie.hostOnly:
    cookie.domain = url.host
  if not hasPath:
    cookie.path = defaultCookiePath(url)
  return ok(cookie)

proc newCookieJar*(url: URL; allowHosts: seq[Regex]): CookieJar =
  return CookieJar(
    domain: url.host,
    allowHosts: allowHosts
  )

proc setCookie*(cookieJar: CookieJar; header: openArray[string]; url: URL) =
  let t = getTime().toUnix()
  for s in header:
    let cookie = parseCookie(s, t, url)
    if cookie.isSome:
      cookieJar.add(cookie.get)
