# See ssl.nim for the entry point.

{.push raises: [].}

from std/strutils import
  split,
  strip

import std/posix

import io/dynstream
import types/opt
import utils/sandbox

import adapter/protocol/lcgi_ssl

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
  TINFL_STATUS_ISIZE_OR_CRC32_MISMATCH = -3
  TINFL_STATUS_ADLER32_MISMATCH = -2
  TINFL_STATUS_FAILED = -1
  TINFL_STATUS_DONE = 0
  TINFL_STATUS_NEEDS_MORE_INPUT = 1
  TINFL_STATUS_HAS_MORE_OUTPUT = 2

type tinfl_huff_table {.importc, header: "tinfl.h", completeStruct.} = object
  m_code_size: array[TINFL_MAX_HUFF_SYMBOLS_0, uint8]
  m_look_up: array[TINFL_FAST_LOOKUP_SIZE, uint16]
  m_tree: array[TINFL_MAX_HUFF_SYMBOLS_0 * 2, uint16]

type tinfl_decompressor {.importc, header: "tinfl.h", completeStruct.} = object
  m_state, m_num_bits, m_zhdr0, m_zhdr1, m_g_isize: uint32
  m_checksum, m_checksum_current: uint32
  m_final, m_type, m_check_adler32, m_dist, m_counter, m_num_extra: uint32
  m_table_sizes: array[TINFL_MAX_HUFF_TABLES, uint32]

  m_bit_buf: uint64
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

const InputBufferSize = 16384

# libbrotli bindings
type BrotliDecoderState {.importc, header: "<brotli/decode.h>",
  incompleteStruct.} = object

type
  uint8PConstPImpl {.importc: "const uint8_t**".} = cstring
  uint8PConstP = distinct uint8PConstPImpl

type BrotliDecoderResult {.size: sizeof(cint).} = enum
  BROTLI_DECODER_RESULT_ERROR = 0
  BROTLI_DECODER_RESULT_SUCCESS = 1
  BROTLI_DECODER_RESULT_NEEDS_MORE_INPUT = 2
  BROTLI_DECODER_RESULT_NEEDS_MORE_OUTPUT = 3

type
  brotli_alloc_func {.importc, header: "<brotli/types.h>".} =
    proc(opaque: pointer; size: csize_t): pointer {.cdecl.}
  brotli_free_func {.importc, header: "<brotli/types.h>".} =
    proc(opaque: pointer; address: pointer): pointer {.cdecl.}

  BrotliDecoderErrorCode = cint

{.push importc, cdecl, header: "<brotli/decode.h>".}
proc BrotliDecoderCreateInstance(alloc_func: brotli_alloc_func;
  free_func: brotli_free_func; opaque: pointer): ptr BrotliDecoderState
proc BrotliDecoderDestroyInstance(state: ptr BrotliDecoderState)
proc BrotliDecoderDecompressStream(state: ptr BrotliDecoderState;
  available_in: var csize_t; next_in: uint8PConstP;
  available_out: var csize_t; next_out: var ptr uint8; total_out: ptr csize_t):
  BrotliDecoderResult
proc BrotliDecoderGetErrorCode(state: ptr BrotliDecoderState):
  BrotliDecoderErrorCode
proc BrotliDecoderErrorString(c: BrotliDecoderErrorCode): cstring
{.pop.}

type
  HTTPHandle = ref object
    state: HTTPState
    bodyState: HTTPState # if TE is chunked, hsChunkSize; else hsBody
    lineState: LineState
    chunkSize: uint64 # Content-Length if TE is not chunked
    ps: DynStream
    os: PosixStream
    line: string
    headers: seq[tuple[key, value: string]]

  LineState = enum
    lsNone, lsCrSeen

  HTTPState = enum
    hsStatus, hsHeaders, hsChunkSize, hsAfterChunk, hsBody, hsTrailers, hsDone

  ContentEncoding = enum
    ceBr = "br"
    ceDeflate = "deflate"
    ceGzip = "gzip"

  TransferEncoding = enum
    teBr = "br"
    teChunked = "chunked"
    teGzip = "gzip"
    teDeflate = "deflate"

proc die(s: string) {.noreturn.} =
  let stderr = cast[ChaFile](stderr)
  discard stderr.writeLine("newhttp: " & s)
  quit(1)

proc inflate(op: HTTPHandle; flag: uint32) =
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
    var iq {.noinit.}: array[InputBufferSize, uint8]
    var oq {.noinit.}: array[TINFL_LZ_DICT_SIZE, uint8]
    var oqoff = 0
    while true:
      let len0 = pins.read(iq)
      if len0 <= 0:
        break
      let len = csize_t(len0)
      var n = csize_t(0)
      while n < len:
        var iqn = csize_t(len) - n
        var oqn = csize_t(oq.len - oqoff)
        let status = decomp.tinfl_decompress(addr iq[n], iqn, addr oq[0],
          addr oq[oqoff], oqn, flags)
        if os.writeLoop(oq.toOpenArray(oqoff, oqoff + int(oqn) - 1)).isErr:
          quit(1)
        oqoff = int((csize_t(oqoff) + oqn) and csize_t(oq.len) - 1)
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
            TINFL_STATUS_ISIZE_OR_CRC32_MISMATCH:
          die($status)
    quit(0)
  else: # parent
    pins.sclose()
    op.os = pouts

proc unbrotli(op: HTTPHandle) =
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
    let decomp = BrotliDecoderCreateInstance(nil, nil, nil)
    var iq {.noinit.}: array[InputBufferSize, uint8]
    var oq {.noinit.}: array[InputBufferSize * 2, uint8]
    while true:
      let len0 = pins.read(iq)
      if len0 <= 0:
        break
      let len = csize_t(len0)
      var n = csize_t(0)
      while true:
        var iqn = csize_t(len) - n
        var oqn = csize_t(oq.len)
        var next_in = addr iq[n]
        var next_out = addr oq[0]
        let next_inP = cast[uint8PConstP](addr next_in)
        let status = decomp.BrotliDecoderDecompressStream(iqn, next_inP, oqn,
          next_out, nil)
        if os.writeLoop(oq.toOpenArray(0, oq.len - int(oqn) - 1)).isErr:
          quit(1)
        n = csize_t(len) - iqn
        case status
        of BROTLI_DECODER_RESULT_NEEDS_MORE_INPUT:
          assert len == n
          break
        of BROTLI_DECODER_RESULT_NEEDS_MORE_OUTPUT:
          discard
        of BROTLI_DECODER_RESULT_SUCCESS:
          decomp.BrotliDecoderDestroyInstance()
          quit(0)
        of BROTLI_DECODER_RESULT_ERROR:
          let c = decomp.BrotliDecoderGetErrorCode()
          die($BrotliDecoderErrorString(c))
    # should be unreachable I think
    die("unexpected end of brotli stream")
  else: # parent
    pins.sclose()
    op.os = pouts

proc handleStatus(op: HTTPHandle; iq: openArray[char]): int =
  for i, c in iq:
    case op.lineState
    of lsNone:
      if c == '\r':
        op.lineState = lsCrSeen
      else:
        op.line &= c
    of lsCrSeen:
      if c != '\n' or
          not op.line.startsWithIgnoreCase("HTTP/1.1") and
          not op.line.startsWithIgnoreCase("HTTP/1.0"):
        quit(1)
      let codes = op.line.until(' ', "HTTP/1.0 ".len)
      let code = parseUInt16(codes)
      if codes.len > 3 or code.isErr:
        quit(1)
      let buf = "Status: " & $code.get & "\r\nCha-Control: ControlDone\r\n"
      if op.os.writeLoop(buf).isErr:
        quit(1)
      op.lineState = lsNone
      op.state = hsHeaders
      op.line = ""
      return i + 1
  return iq.len

proc handleHeaders(op: HTTPHandle; iq: openArray[char]): int =
  for i, c in iq:
    case op.lineState
    of lsNone:
      if c == '\r':
        op.lineState = lsCrSeen
      else:
        op.line &= c
    of lsCrSeen:
      if c != '\n': # malformed header
        quit(1)
      if op.line != "":
        var name = op.line.until(':')
        if name.len > 0 and name[0] notin HTTPWhitespace and
            name.len != op.line.len:
          name = name.strip(leading = false, trailing = true,
            chars = HTTPWhitespace)
          let value = op.line.after(':').strip(leading = true,
            trailing = false, chars = HTTPWhitespace)
          op.headers.add((move(name), value))
        op.line = ""
        op.lineState = lsNone
      else:
        var buf = ""
        var contentEncodings: seq[ContentEncoding] = @[]
        var transferEncodings: seq[TransferEncoding] = @[]
        var contentLength = uint64.high
        for it in op.headers:
          buf &= it.key & ": " & it.value & "\r\n"
          if it.key.equalsIgnoreCase("Content-Encoding"):
            for it in it.value.split(','):
              if ce := parseEnumNoCase[ContentEncoding](it):
                contentEncodings.add(ce)
          elif it.key.equalsIgnoreCase("Transfer-Encoding"):
            for it in it.value.split(','):
              if te := parseEnumNoCase[TransferEncoding](it):
                transferEncodings.add(te)
          elif it.key.equalsIgnoreCase("Content-Length"):
            contentLength = parseUInt64(it.value).get(uint64.high)
        buf &= "\r\n"
        if op.os.writeLoop(buf).isErr:
          quit(1)
        for ce in contentEncodings.ritems:
          case ce
          of ceBr: op.unbrotli()
          of ceGzip: op.inflate(TINFL_FLAG_PARSE_GZIP_HEADER)
          of ceDeflate: op.inflate(TINFL_FLAG_PARSE_ZLIB_HEADER)
        op.bodyState = hsBody
        for i in countdown(transferEncodings.high, 0):
          case transferEncodings[i]
          of teBr: op.unbrotli()
          of teChunked:
            if i == 0:
              op.bodyState = hsChunkSize
          of teGzip: op.inflate(TINFL_FLAG_PARSE_GZIP_HEADER)
          of teDeflate: op.inflate(TINFL_FLAG_PARSE_ZLIB_HEADER)
        op.lineState = lsNone
        op.state = op.bodyState
        if op.bodyState == hsBody:
          op.chunkSize = contentLength
        return i + 1
  return iq.len

proc handleChunkSize(op: HTTPHandle; iq: openArray[char]): int =
  for i, c in iq:
    case op.lineState
    of lsNone:
      if c == '\r':
        op.lineState = lsCrSeen
      else:
        let n = hexValue(c)
        let osize = op.chunkSize
        op.chunkSize = osize * 0x10 + uint64(n)
        if n == -1 or osize > op.chunkSize:
          die("error decoding chunk size")
    of lsCrSeen:
      if c != '\n':
        die("CRLF expected")
      op.lineState = lsNone
      if op.chunkSize > 0:
        op.state = hsBody
        return i + 1
      op.state = hsTrailers
      break
  return iq.len

proc handleBody(op: HTTPHandle; iq: openArray[char]): int =
  var L = uint64(iq.len)
  if L >= op.chunkSize:
    L = op.chunkSize
    op.state = hsAfterChunk
  let n = int(L)
  if op.os.writeLoop(iq.toOpenArray(0, n - 1)).isErr:
    quit(1)
  op.chunkSize -= L
  if op.bodyState == hsBody and op.chunkSize == 0:
    return -1 # we're done
  return n

proc handleAfterChunk(op: HTTPHandle; iq: openArray[char]): int =
  for i, c in iq:
    case op.lineState
    of lsNone:
      if c != '\r':
        quit(1)
      op.lineState = lsCrSeen
    of lsCrSeen:
      if c != '\n':
        quit(1)
      op.lineState = lsNone
      op.state = hsChunkSize
      return i + 1
  return iq.len

proc handleTrailers(op: HTTPHandle; iq: openArray[char]): int =
  for i, c in iq:
    case op.lineState
    of lsNone:
      if c == '\r':
        op.lineState = lsCrSeen
      else:
        op.line &= c
    of lsCrSeen:
      if c != '\n':
        quit(1)
      op.lineState = lsNone
      if op.line == "":
        op.state = hsDone
        return i + 1
      op.line = ""
  return iq.len

proc handleBuffer(op: HTTPHandle; iq: openArray[char]): int =
  case op.state
  of hsStatus: return op.handleStatus(iq)
  of hsHeaders: return op.handleHeaders(iq)
  of hsChunkSize: return op.handleChunkSize(iq)
  of hsBody: return op.handleBody(iq)
  of hsAfterChunk: return op.handleAfterChunk(iq) # CRLF after a chunk
  of hsTrailers: return op.handleTrailers(iq)
  of hsDone: return -1

proc checkCert(ssl: ptr SSL) =
  let res = SSL_get_verify_result(ssl)
  if res != X509_V_OK:
    let s = X509_verify_cert_error_string(res)
    cgiDie(ceInvalidResponse, s)

proc main*() =
  let secure = getEnvEmpty("MAPPED_URI_SCHEME") == "https"
  let username = getEnvEmpty("MAPPED_URI_USERNAME")
  let password = getEnvEmpty("MAPPED_URI_PASSWORD")
  let host = getEnvEmpty("MAPPED_URI_HOST")
  let port = getEnvEmpty("MAPPED_URI_PORT", if secure: "443" else: "80")
  let path = getEnvEmpty("MAPPED_URI_PATH", "/")
  let query = getEnvEmpty("MAPPED_URI_QUERY")
  let os = newPosixStream(STDOUT_FILENO)
  let ps = if secure:
    let ssl = connectSSLSocket(host, port, useDefaultCA = true).orDie()
    if getEnvEmpty("CHA_INSECURE_SSL_NO_VERIFY", "0") != "1":
      checkCert(ssl)
    newSSLStream(ssl)
  else:
    connectSocket(host, port).orDie()
  let op = HTTPHandle(ps: ps, os: os)
  let requestMethod = getEnvEmpty("REQUEST_METHOD")
  var buf = requestMethod & ' ' & path
  if query != "":
    buf &= '?' & query
  buf &= " HTTP/1.1\r\n"
  buf &= "Host: " & host
  if secure and port != "443" or not secure and port != "80":
    buf &= ':' & port
  buf &= "\r\n"
  buf &= "Connection: close\r\n"
  if username != "":
    buf &= "Authorization: Basic " & btoa(username & ':' & password) & "\r\n"
  let contentLength = getEnvEmpty("CONTENT_LENGTH")
  if n := parseUInt64(contentLength):
    buf &= "Content-Length: " & $n & "\r\n"
  buf &= getEnvEmpty("REQUEST_HEADERS")
  buf &= "\r\n"
  op.ps.writeLoop(buf)
    .orDie(ceConnectionRefused, "error sending request header")
  var iq {.noinit.}: array[InputBufferSize, char]
  if requestMethod == "POST":
    let ps = newPosixStream(STDIN_FILENO)
    while (let n = ps.read(iq); n > 0):
      op.ps.writeLoop(iq.toOpenArray(0, n - 1))
        .orDie(ceConnectionRefused, "error sending request body")
  if os.writeLoop("Cha-Control: Connected\r\n").isErr:
    quit(1)
  block readResponse:
    while (let n = ps.read(iq); n > 0):
      var m = 0
      while m < n:
        let k = op.handleBuffer(iq.toOpenArray(m, n - 1))
        if k == -1: # hsDone
          break readResponse
        m += k
  op.ps.sclose()

{.pop.} # raises: []
