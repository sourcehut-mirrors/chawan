# w3m's URI method map format.

import std/strutils
import std/tables

import types/opt
import types/url
import utils/twtstr

type URIMethodMap* = object
  map*: Table[string, string]
  imageProtos*: seq[string]

func rewriteURL(pattern, surl: string): string =
  result = ""
  var was_perc = false
  for c in pattern:
    if was_perc:
      if c == '%':
        result &= '%'
      elif c == 's':
        result &= surl
      else:
        result &= '%'
        result &= c
      was_perc = false
    elif c != '%':
      result &= c
    else:
      was_perc = true
  if was_perc:
    result &= '%'

type URIMethodMapResult* = enum
  ummrNotFound, ummrSuccess, ummrWrongURL

proc findAndRewrite*(this: URIMethodMap; url: var URL): URIMethodMapResult =
  let s = this.map.getOrDefault(url.protocol)
  if s != "":
    let surl = s.rewriteURL($url)
    if x := newURL(surl):
      url = x
      return ummrSuccess
    return ummrWrongURL
  return ummrNotFound

proc insert(this: var URIMethodMap; k, v: string) =
  if not this.map.hasKeyOrPut(k, v) and k.startsWith("img-codec+"):
    this.imageProtos.add(k.until(':'))

proc parseURIMethodMap*(this: var URIMethodMap; s: string) =
  for line in s.split('\n'):
    if line.len == 0 or line[0] == '#':
      continue # comments
    var k = ""
    var i = 0
    while i < line.len and line[i] notin AsciiWhitespace + {':'}:
      k &= line[i].toLowerAscii()
      inc i
    if i >= line.len or line[i] != ':':
      continue # invalid
    k &= ':'
    inc i # skip colon
    while i < line.len and line[i] in AsciiWhitespace:
      inc i
    var v = line.until(AsciiWhitespace, i)
    # Basic w3m compatibility.
    # If needed, w3m-cgi-compat covers more cases.
    if v.startsWith("file:/cgi-bin/"):
      v = "cgi-bin:" & v.substr("file:/cgi-bin/".len)
    elif v.startsWith("file:///cgi-bin/"):
      v = "cgi-bin:" & v.substr("file:///cgi-bin/".len)
    elif v.startsWith("/cgi-bin/"):
      v = "cgi-bin:" & v.substr("/cgi-bin/".len)
    this.insert(k, v)

proc parseURIMethodMap*(s: string): URIMethodMap =
  result = URIMethodMap()
  result.parseURIMethodMap(s)

proc append*(this: var URIMethodMap; that: URIMethodMap) =
  for k, v in that.map:
    this.insert(k, v)
