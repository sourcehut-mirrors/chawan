import std/envvars
import std/posix
import std/strutils

import io/dynstream
import utils/sandbox

import adapter/protocol/curl

template setopt(curl: CURL; opt: CURLoption; arg: typed) =
  discard curl_easy_setopt(curl, opt, arg)

template setopt(curl: CURL; opt: CURLoption; arg: string) =
  discard curl_easy_setopt(curl, opt, cstring(arg))

template getinfo(curl: CURL; info: CURLINFO; arg: typed) =
  discard curl_easy_getinfo(curl, info, arg)

template set(url: CURLU; part: CURLUPart; content: cstring; flags: cuint) =
  discard curl_url_set(url, part, content, flags)

template set(url: CURLU; part: CURLUPart; content: string; flags: cuint) =
  url.set(part, cstring(content), flags)

func curlErrorToChaError(res: CURLcode): string =
  return case res
  of CURLE_OK: ""
  of CURLE_URL_MALFORMAT: "InvalidURL" #TODO should never occur...
  of CURLE_COULDNT_CONNECT: "ConnectionRefused"
  of CURLE_COULDNT_RESOLVE_PROXY: "FailedToResolveProxy"
  of CURLE_COULDNT_RESOLVE_HOST: "FailedToResolveHost"
  of CURLE_PROXY: "ProxyRefusedToConnect"
  else: "InternalError"

proc getCurlConnectionError(res: CURLcode): string =
  let e = curlErrorToChaError(res)
  let msg = $curl_easy_strerror(res)
  return "Cha-Control: ConnectionError " & e & " " & msg & "\n"

# tinfl bindings, see tinfl.h for details
const
  TINFL_MAX_HUFF_TABLES = 3
  TINFL_MAX_HUFF_SYMBOLS_0 = 288
  TINFL_MAX_HUFF_SYMBOLS_1 = 32
  TINFL_FAST_LOOKUP_BITS = 10
  TINFL_FAST_LOOKUP_SIZE = 1 shl TINFL_FAST_LOOKUP_BITS

const TINFL_LZ_DICT_SIZE = 32768

const
  TINFL_FLAG_PARSE_ZLIB_HEADER = 0x01u32
  TINFL_FLAG_PARSE_GZIP_HEADER = 0x02u32
  TINFL_FLAG_HAS_MORE_INPUT = 0x04u32
  TINFL_FLAG_USING_NON_WRAPPING_OUTPUT_BUF* = 0x08u32

type tinfl_status {.size: sizeof(cint).} = enum
  TINFL_STATUS_FAILED_CANNOT_MAKE_PROGRESS = -5
  TINFL_STATUS_BAD_PARAM = -4
  TINFL_STATUS_GZIP_ISIZE_OR_CRC32_MISMATCH = -3
  TINFL_STATUS_ADLER32_MISMATCH = -2
  TINFL_STATUS_FAILED = -1
  TINFL_STATUS_DONE = 0
  TINFL_STATUS_NEEDS_MORE_INPUT = 1
  TINFL_STATUS_HAS_MORE_OUTPUT = 2

when sizeof(int) == 8:
  type tinfl_bit_buf = uint64
else:
  type tinfl_bit_buf = uint32

type tinfl_huff_table {.importc, header: "tinfl.h", completeStruct.} = object
  m_code_size: array[TINFL_MAX_HUFF_SYMBOLS_0, uint8]
  m_look_up: array[TINFL_FAST_LOOKUP_SIZE, uint16]
  m_tree: array[TINFL_MAX_HUFF_SYMBOLS_0 * 2, uint16]

type tinfl_decompressor {.importc, header: "tinfl.h", completeStruct.} = object
  m_state, m_num_bits, m_zhdr0, m_zhdr1, m_g_isize: uint32
  m_checksum, m_checksum_current: uint32
  m_final, m_type, m_check_adler32, m_dist, m_counter, m_num_extra: uint32
  m_table_sizes: array[TINFL_MAX_HUFF_TABLES, uint32]

  m_bit_buf: tinfl_bit_buf
  m_dist_from_out_buf_start: csize_t
  m_tables: array[TINFL_MAX_HUFF_TABLES, tinfl_huff_table]

  m_raw_header: array[4, uint8]
  m_len_codes: array[TINFL_MAX_HUFF_SYMBOLS_0 + TINFL_MAX_HUFF_SYMBOLS_1 + 137,
    uint8]
  m_gz_header: array[10, uint8]

{.push importc, cdecl, header: """
#define TINFL_IMPLEMENTATION
#include "tinfl.h"
""".}
proc tinfl_decompress(r: var tinfl_decompressor; pIn_buf_next: ptr uint8;
  pIn_buf_size: var csize_t; pOut_buf_start, pOut_buf_next: ptr uint8;
  pOut_buf_size: var csize_t; decomp_flags: uint32): tinfl_status
{.pop.} # importc, cdecl, header: "tinfl.h"

type
  EarlyHintState = enum
    ehsNone, ehsStarted, ehsDone

  HttpHandle = ref object
    curl: CURL
    os: PosixStream
    statusline: bool
    connectreport: bool
    earlyhint: EarlyHintState
    slist: curl_slist

proc inflate(op: HttpHandle; flag: uint32) =
  var pipefd {.noinit.}: array[2, cint]
  if pipe(pipefd) != 0:
    return
  let pins = newPosixStream(pipefd[0])
  let pouts = newPosixStream(pipefd[1])
  case fork()
  of -1:
    pins.sclose()
    pouts.sclose()
  of 0: # child
    enterNetworkSandbox()
    pouts.sclose()
    let os = op.os
    var flags = flag or TINFL_FLAG_HAS_MORE_INPUT
    var decomp = tinfl_decompressor()
    # curl's default buffer size is 16k
    var iq {.noinit.}: array[16384, uint8]
    var oq {.noinit.}: array[TINFL_LZ_DICT_SIZE, uint8]
    var oqoff = csize_t(0)
    while true:
      let len0 = pins.readData(iq)
      if len0 <= 0:
        break
      let len = csize_t(len0)
      var n = csize_t(0)
      while n < len:
        var iqn = csize_t(len) - n
        var oqn = csize_t(oq.len) - oqoff
        let status = decomp.tinfl_decompress(addr iq[n], iqn, addr oq[0],
          addr oq[oqoff], oqn, flags)
        if oqn > 0:
          if not os.writeDataLoop(oq.toOpenArray(oqoff, oqoff + oqn - 1)):
            quit(1)
        oqoff = (oqoff + oqn) and csize_t(oq.len - 1)
        n += iqn
        case status
        of TINFL_STATUS_HAS_MORE_OUTPUT:
          discard
        of TINFL_STATUS_NEEDS_MORE_INPUT:
          assert len == n
        of TINFL_STATUS_DONE:
          quit(0)
        of TINFL_STATUS_BAD_PARAM: assert false
        of TINFL_STATUS_ADLER32_MISMATCH, TINFL_STATUS_FAILED,
            TINFL_STATUS_FAILED_CANNOT_MAKE_PROGRESS,
            TINFL_STATUS_GZIP_ISIZE_OR_CRC32_MISMATCH:
          stderr.writeLine("NewHTTP error: " & $status)
          quit(1)
    quit(0)
  else: # parent
    pins.sclose()
    op.os = pouts

proc strcasecmp(a, b: cstring): cint {.importc, header: "<strings.h>".}

proc curlWriteHeader(p: cstring; size, nitems: csize_t; userdata: pointer):
    csize_t {.cdecl.} =
  var line = newString(nitems)
  if nitems > 0:
    copyMem(addr line[0], p, nitems)
  let op = cast[HttpHandle](userdata)
  if not op.statusline:
    op.statusline = true
    var status: clong
    op.curl.getinfo(CURLINFO_RESPONSE_CODE, addr status)
    if status == 103:
      op.earlyhint = ehsStarted
    else:
      op.connectreport = true
      op.os.write("Status: " & $status & "\nCha-Control: ControlDone\n")
    return nitems
  if line == "\r\n" or line == "\n":
    # empty line (last, before body)
    if op.earlyhint == ehsStarted:
      # ignore; we do not have a way to stream headers yet.
      op.earlyhint = ehsDone
      # reset statusline; we are awaiting the next line.
      op.statusline = false
      return nitems
    op.os.write("\r\n")
    var hdr: ptr curl_header
    var i = csize_t(0)
    while op.curl.curl_easy_header("Content-Encoding", i, CURLH_HEADER, -1,
        hdr) == 0:
      if strcasecmp(hdr.value, "gzip") == 0:
        op.inflate(TINFL_FLAG_PARSE_GZIP_HEADER)
      elif strcasecmp(hdr.value, "deflate") == 0:
        op.inflate(TINFL_FLAG_PARSE_ZLIB_HEADER)
      #TODO brotli, zstd
      hdr = curl_easy_nextheader(op.curl, CURLH_HEADER, -1, hdr)
      inc i
    return nitems
  if op.earlyhint != ehsStarted:
    # Regrettably, we can only write early hint headers after the status
    # code is already known.
    # For now, it seems easiest to just ignore them all.
    op.os.write(line)
  return nitems

# From the documentation: size is always 1.
proc curlWriteBody(p: cstring; size, nmemb: csize_t; userdata: pointer):
    csize_t {.cdecl.} =
  let op = cast[HttpHandle](userdata)
  return csize_t(op.os.writeData(p, int(nmemb)))

# From the documentation: size is always 1.
proc readFromStdin(p: pointer; size, nitems: csize_t; userdata: pointer):
    csize_t {.cdecl.} =
  return csize_t(read(STDIN_FILENO, p, int(nitems)))

proc curlPreRequest(clientp: pointer; conn_primary_ip, conn_local_ip: cstring;
    conn_primary_port, conn_local_port: cint): cint {.cdecl.} =
  let op = cast[HttpHandle](clientp)
  op.connectreport = true
  op.os.write("Cha-Control: Connected\n")
  return 0 # ok

proc main() =
  let curl = curl_easy_init()
  doAssert curl != nil
  let url = curl_url()
  const flags = cuint(CURLU_PATH_AS_IS)
  url.set(CURLUPART_SCHEME, getEnv("MAPPED_URI_SCHEME"), flags)
  let username = getEnv("MAPPED_URI_USERNAME")
  if username != "":
    url.set(CURLUPART_USER, username, flags)
  let password = getEnv("MAPPED_URI_PASSWORD")
  if password != "":
    url.set(CURLUPART_PASSWORD, password, flags)
  url.set(CURLUPART_HOST, getEnv("MAPPED_URI_HOST"), flags)
  let port = getEnv("MAPPED_URI_PORT")
  if port != "":
    url.set(CURLUPART_PORT, port, flags)
  let path = getEnv("MAPPED_URI_PATH")
  if path != "":
    url.set(CURLUPART_PATH, path, flags)
  let query = getEnv("MAPPED_URI_QUERY")
  if query != "":
    url.set(CURLUPART_QUERY, query, flags)
  if getEnv("CHA_INSECURE_SSL_NO_VERIFY") == "1":
    curl.setopt(CURLOPT_SSL_VERIFYPEER, 0)
    curl.setopt(CURLOPT_SSL_VERIFYHOST, 0)
  curl.setopt(CURLOPT_CURLU, url)
  let os = newPosixStream(STDOUT_FILENO)
  let op = HttpHandle(curl: curl, os: os)
  curl.setopt(CURLOPT_SUPPRESS_CONNECT_HEADERS, 1)
  curl.setopt(CURLOPT_WRITEDATA, op)
  curl.setopt(CURLOPT_WRITEFUNCTION, curlWriteBody)
  curl.setopt(CURLOPT_HEADERDATA, op)
  curl.setopt(CURLOPT_HEADERFUNCTION, curlWriteHeader)
  curl.setopt(CURLOPT_PREREQDATA, op)
  curl.setopt(CURLOPT_PREREQFUNCTION, curlPreRequest)
  curl.setopt(CURLOPT_NOSIGNAL, 1)
  let proxy = getEnv("ALL_PROXY")
  if proxy != "":
    curl.setopt(CURLOPT_PROXY, proxy)
  case getEnv("REQUEST_METHOD")
  of "GET":
    curl.setopt(CURLOPT_HTTPGET, 1)
  of "POST":
    curl.setopt(CURLOPT_POST, 1)
    let len = parseInt(getEnv("CONTENT_LENGTH"))
    # > For any given platform/compiler curl_off_t must be typedef'ed to
    # a 64-bit
    # > wide signed integral data type. The width of this data type must remain
    # > constant and independent of any possible large file support settings.
    # >
    # > As an exception to the above, curl_off_t shall be typedef'ed to
    # a 32-bit
    # > wide signed integral data type if there is no 64-bit type.
    # It seems safe to assume that if the platform has no uint64 then Nim won't
    # compile either. In return, we are allowed to post >2G of data.
    curl.setopt(CURLOPT_POSTFIELDSIZE_LARGE, uint64(len))
    curl.setopt(CURLOPT_READFUNCTION, readFromStdin)
  let headers = getEnv("REQUEST_HEADERS")
  for line in headers.split("\r\n"):
    # This is OK, because curl_slist_append strdup's line.
    op.slist = curl_slist_append(op.slist, cstring(line))
  if op.slist != nil:
    curl.setopt(CURLOPT_HTTPHEADER, op.slist)
  let res = curl_easy_perform(curl)
  if res != CURLE_OK and not op.connectreport:
    op.os.write(getCurlConnectionError(res))
    op.connectreport = true
  curl_easy_cleanup(curl)

main()
