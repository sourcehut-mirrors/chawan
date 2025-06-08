when NimMajor >= 2:
  import std/envvars
else:
  import std/os
import std/posix
import std/strutils
import utils/sandbox

const curllib = (func(): string =
  const curlLibName {.strdefine.} = ""
  when curlLibName != "":
    return curlLibName
  elif defined(macosx):
    return "libcurl(|.4|.4.8.0).dylib"
  else: # assume elf
    return "libcurl.so(|.4|.4.8.0)"
)()

const
  CURL_GLOBAL_SSL* = 1 shl 0 # no purpose since 7.57.0
  CURL_GLOBAL_WIN32* = 1 shl 1
  CURL_GLOBAL_ALL* = CURL_GLOBAL_SSL or CURL_GLOBAL_WIN32
  CURL_GLOBAL_NOTHING* = 0
  CURL_GLOBAL_DEFAULT* = CURL_GLOBAL_ALL
  CURL_GLOBAL_ACK_EINTR* = 1 shl 2

const
  CURLOPTTYPE_LONG = 0
  CURLOPTTYPE_OBJECTPOINT = 10000
  CURLOPTTYPE_FUNCTIONPOINT = 20000
  CURLOPTTYPE_OFF_T = 30000
  CURLOPTTYPE_BLOB = 40000

const
  CURLOPTTYPE_STRINGPOINT = CURLOPTTYPE_OBJECTPOINT
  CURLOPTTYPE_SLISTPOINT = CURLOPTTYPE_OBJECTPOINT
  CURLOPTTYPE_CBPOINT = CURLOPTTYPE_OBJECTPOINT
  CURLOPTTYPE_VALUES = CURLOPTTYPE_LONG

const
  CURLINFO_STRING = 0x100000
  CURLINFO_LONG = 0x200000
  CURLINFO_DOUBLE = 0x300000
  CURLINFO_SLIST = 0x400000
  CURLINFO_PTR = 0x400000 # same as SLIST
  CURLINFO_SOCKET = 0x500000
  CURLINFO_OFF_T = 0x600000
  CURLINFO_MASK {.used.} = 0x0fffff
  CURLINFO_TYPEMASK {.used.} = 0xf00000

const
  CURL_WAIT_POLLIN* = 0x0001
  CURL_WAIT_POLLPRI* = 0x0002
  CURL_WAIT_POLLOUT* = 0x0004

# CURLU
const
  CURLU_DEFAULT_PORT* = (1 shl 0)       # return default port number
  CURLU_NO_DEFAULT_PORT* = (1 shl 1)    # act as if no port number was set,
                                        # if the port number matches the
                                        # default for the scheme
  CURLU_DEFAULT_SCHEME* = (1 shl 2)     # return default scheme if missing
  CURLU_NON_SUPPORT_SCHEME* = (1 shl 3) # allow non-supported scheme
  CURLU_PATH_AS_IS* = (1 shl 4)         # leave dot sequences
  CURLU_DISALLOW_USER* = (1 shl 5)      # no user+password allowed
  CURLU_URLDECODE* = (1 shl 6)          # URL decode on get
  CURLU_URLENCODE* = (1 shl 7)          # URL encode on set
  CURLU_APPENDQUERY* = (1 shl 8)        # append a form style part
  CURLU_GUESS_SCHEME* = (1 shl 9)       # legacy curl-style guessing
  CURLU_NO_AUTHORITY* = (1 shl 10)      # Allow empty authority when the scheme
                                        # is unknown.
  CURLU_ALLOW_SPACE* = (1 shl 11)       # Allow spaces in the URL
  CURLU_PUNYCODE* = (1 shl 12)          # get the host name in punycode
  CURLU_PUNY2IDN* = (1 shl 13)          # punycode => IDN conversion

const
  CURLH_HEADER* = 1 shl 0
  CURLH_TRAILER* = 1 shl 1
  CURLH_CONNECT* = 1 shl 2
  CURLH_1XX* = 1 shl 3
  CURLH_PSEUDO* = 1 shl 4

{.push cdecl, dynlib: curllib.}

type
  CURL* = distinct pointer
  CURLM* = distinct pointer
  CURLU* = distinct pointer

  curl_mime_struct = object
  curl_mime* = ptr curl_mime_struct
  curl_mimepart_struct = object
  curl_mimepart* = ptr curl_mimepart_struct
  curl_slist_struct = object
  curl_slist* = ptr curl_slist_struct
  curl_socket_t = cint
  curl_waitfd* = object
    fd*: curl_socket_t
    events*: cshort
    revents*: cshort # this is, in fact, supported.
  CURLMsg_data {.union.} = object
    whatever: pointer
    result*: CURLcode
  CURLMsg_struct = object
    msg*: CURLMSG_E
    easy_handle*: CURL
    data*: CURLMsg_data
  CURLMsg* = ptr CURLMsg_struct

  CURLoption* {.size: sizeof(cint).} = enum
    # Long
    CURLOPT_PORT = CURLOPTTYPE_LONG + 3
    CURLOPT_SSLVERSION = CURLOPTTYPE_VALUES + 32
    CURLOPT_TIMECONDITION = CURLOPTTYPE_VALUES + 33
    CURLOPT_POST = CURLOPTTYPE_LONG + 47
    CURLOPT_DIRLISTONLY = CURLOPTTYPE_LONG + 48
    CURLOPT_FOLLOWLOCATION = CURLOPTTYPE_LONG + 52
    CURLOPT_POSTFIELDSIZE = CURLOPTTYPE_LONG + 60
    CURLOPT_SSL_VERIFYPEER = CURLOPTTYPE_LONG + 64
    CURLOPT_HTTPGET = CURLOPTTYPE_LONG + 80
    CURLOPT_SSL_VERIFYHOST = CURLOPTTYPE_LONG + 81
    CURLOPT_NOSIGNAL = CURLOPTTYPE_LONG + 99
    CURLOPT_FTP_FILEMETHOD = CURLOPTTYPE_VALUES + 138
    CURLOPT_CONNECT_ONLY = CURLOPTTYPE_LONG + 141
    CURLOPT_SUPPRESS_CONNECT_HEADERS = CURLOPTTYPE_LONG + 265

    # Objectpoint
    CURLOPT_WRITEDATA = CURLOPTTYPE_CBPOINT + 1
    CURLOPT_URL = CURLOPTTYPE_STRINGPOINT + 2
    CURLOPT_PROXY = CURLOPTTYPE_STRINGPOINT + 4
    CURLOPT_ERRORBUFFER = CURLOPTTYPE_OBJECTPOINT + 10
    CURLOPT_POSTFIELDS = CURLOPTTYPE_OBJECTPOINT + 15
    CURLOPT_HTTPHEADER = CURLOPTTYPE_SLISTPOINT + 23
    CURLOPT_KEYPASSWD = CURLOPTTYPE_STRINGPOINT + 26
    CURLOPT_HEADERDATA = CURLOPTTYPE_CBPOINT + 29
    CURLOPT_ACCEPT_ENCODING = CURLOPTTYPE_STRINGPOINT + 102
    CURLOPT_SSH_PUBLIC_KEYFILE = CURLOPTTYPE_STRINGPOINT + 152
    CURLOPT_SSH_PRIVATE_KEYFILE = CURLOPTTYPE_STRINGPOINT + 153
    CURLOPT_MIMEPOST = CURLOPTTYPE_OBJECTPOINT + 269
    CURLOPT_CURLU = CURLOPTTYPE_OBJECTPOINT + 282
    CURLOPT_PREREQDATA = CURLOPTTYPE_CBPOINT + 313

    # Functionpoint
    CURLOPT_WRITEFUNCTION = CURLOPTTYPE_FUNCTIONPOINT + 11
    CURLOPT_READFUNCTION = CURLOPTTYPE_FUNCTIONPOINT + 12
    CURLOPT_HEADERFUNCTION = CURLOPTTYPE_FUNCTIONPOINT + 79
    CURLOPT_PREREQFUNCTION = CURLOPTTYPE_FUNCTIONPOINT + 312

    # Off-t
    CURLOPT_INFILESIZE_LARGE = CURLOPTTYPE_OFF_T + 115
    CURLOPT_RESUME_FROM_LARGE = CURLOPTTYPE_OFF_T + 116
    CURLOPT_POSTFIELDSIZE_LARGE = CURLOPTTYPE_OFF_T + 120

    # Blob
    CURLOPT_SSLCERT_BLOB = CURLOPTTYPE_BLOB + 291
    CURLOPT_SSLKEY_BLOB = CURLOPTTYPE_BLOB + 292
    CURLOPT_PROXY_SSLCERT_BLOB = CURLOPTTYPE_BLOB + 293
    CURLOPT_PROXY_SSLKEY_BLOB = CURLOPTTYPE_BLOB + 294
    CURLOPT_ISSUECERT_BLOB = CURLOPTTYPE_BLOB + 295

  CURLINFO* {.size: sizeof(cint).} = enum
    CURLINFO_NONE # first, never use this

    # String
    CURLINFO_REDIRECT_URL = CURLINFO_STRING + 31

    # Long
    CURLINFO_RESPONSE_CODE = CURLINFO_LONG + 2

    # Double
    CURLINFO_TOTAL_TIME = CURLINFO_DOUBLE + 3

    # S-list
    CURLINFO_SSL_ENGINES = CURLINFO_SLIST + 27
    CURLINFO_COOKIELIST = CURLINFO_SLIST + 28

    # Pointer
    CURLINFO_CERTINFO = CURLINFO_PTR + 34
    CURLINFO_TLS_SESSION = CURLINFO_PTR + 43
    CURLINFO_TLS_SSL_PTR = CURLINFO_PTR + 45

    # Socket
    CURLINFO_ACTIVESOCKET = CURLINFO_SOCKET + 44

    # Off_t
    CURLINFO_SIZE_UPLOAD_T = CURLINFO_OFF_T + 7
    CURLINFO_SIZE_DOWNLOAD_T = CURLINFO_OFF_T + 9

  CURLcode* {.size: sizeof(cint).} = enum
    CURLE_OK = 0,
    CURLE_UNSUPPORTED_PROTOCOL,    # 1
    CURLE_FAILED_INIT,             # 2
    CURLE_URL_MALFORMAT,           # 3
    CURLE_NOT_BUILT_IN,            # 4 - [was obsoleted in August 2007 for
                                   # 7.17.0, reused in April 2011 for 7.21.5]
    CURLE_COULDNT_RESOLVE_PROXY,   # 5
    CURLE_COULDNT_RESOLVE_HOST,    # 6
    CURLE_COULDNT_CONNECT,         # 7
    CURLE_WEIRD_SERVER_REPLY,      # 8
    CURLE_REMOTE_ACCESS_DENIED,    # 9 a service was denied by the server
                                   # due to lack of access - when login fails
                                   # this is not returned.
    CURLE_FTP_ACCEPT_FAILED,       # 10 - [was obsoleted in April 2006 for
                                   # 7.15.4, reused in Dec 2011 for 7.24.0]
    CURLE_FTP_WEIRD_PASS_REPLY,    # 11
    CURLE_FTP_ACCEPT_TIMEOUT,      # 12 - timeout occurred accepting server
                                   # [was obsoleted in August 2007 for 7.17.0,
                                   # reused in Dec 2011 for 7.24.0]
    CURLE_FTP_WEIRD_PASV_REPLY,    # 13
    CURLE_FTP_WEIRD_227_FORMAT,    # 14
    CURLE_FTP_CANT_GET_HOST,       # 15
    CURLE_HTTP2,                   # 16 - A problem in the http2 framing layer.
                                   # [was obsoleted in August 2007 for 7.17.0,
                                   # reused in July 2014 for 7.38.0]
    CURLE_FTP_COULDNT_SET_TYPE,    # 17
    CURLE_PARTIAL_FILE,            # 18
    CURLE_FTP_COULDNT_RETR_FILE,   # 19
    CURLE_OBSOLETE20,              # 20 - NOT USED
    CURLE_QUOTE_ERROR,             # 21 - quote command failure
    CURLE_HTTP_RETURNED_ERROR,     # 22
    CURLE_WRITE_ERROR,             # 23
    CURLE_OBSOLETE24,              # 24 - NOT USED
    CURLE_UPLOAD_FAILED,           # 25 - failed upload "command"
    CURLE_READ_ERROR,              # 26 - couldn't open/read from file
    CURLE_OUT_OF_MEMORY,           # 27
    CURLE_OPERATION_TIMEDOUT,      # 28 - the timeout time was reached
    CURLE_OBSOLETE29,              # 29 - NOT USED
    CURLE_FTP_PORT_FAILED,         # 30 - FTP PORT operation failed
    CURLE_FTP_COULDNT_USE_REST,    # 31 - the REST command failed
    CURLE_OBSOLETE32,              # 32 - NOT USED
    CURLE_RANGE_ERROR,             # 33 - RANGE "command" didn't work
    CURLE_HTTP_POST_ERROR,         # 34
    CURLE_SSL_CONNECT_ERROR,       # 35 - wrong when connecting with SSL
    CURLE_BAD_DOWNLOAD_RESUME,     # 36 - couldn't resume download
    CURLE_FILE_COULDNT_READ_FILE,  # 37
    CURLE_LDAP_CANNOT_BIND,        # 38
    CURLE_LDAP_SEARCH_FAILED,      # 39
    CURLE_OBSOLETE40,              # 40 - NOT USED
    CURLE_FUNCTION_NOT_FOUND,      # 41 - NOT USED starting with 7.53.0
    CURLE_ABORTED_BY_CALLBACK,     # 42
    CURLE_BAD_FUNCTION_ARGUMENT,   # 43
    CURLE_OBSOLETE44,              # 44 - NOT USED
    CURLE_INTERFACE_FAILED,        # 45 - CURLOPT_INTERFACE failed
    CURLE_OBSOLETE46,              # 46 - NOT USED
    CURLE_TOO_MANY_REDIRECTS,      # 47 - catch endless re-direct loops
    CURLE_UNKNOWN_OPTION,          # 48 - User specified an unknown option
    CURLE_SETOPT_OPTION_SYNTAX,    # 49 - Malformed setopt option
    CURLE_OBSOLETE50,              # 50 - NOT USED
    CURLE_OBSOLETE51,              # 51 - NOT USED
    CURLE_GOT_NOTHING,             # 52 - when this is a specific error
    CURLE_SSL_ENGINE_NOTFOUND,     # 53 - SSL crypto engine not found
    CURLE_SSL_ENGINE_SETFAILED,    # 54 - can not set SSL crypto engine as
                                   # default
    CURLE_SEND_ERROR,              # 55 - failed sending network data
    CURLE_RECV_ERROR,              # 56 - failure in receiving network data
    CURLE_OBSOLETE57,              # 57 - NOT IN USE
    CURLE_SSL_CERTPROBLEM,         # 58 - problem with the local certificate
    CURLE_SSL_CIPHER,              # 59 - couldn't use specified cipher
    CURLE_PEER_FAILED_VERIFICATION, # 60 - peer's certificate or fingerprint
                                   # wasn't verified fine
    CURLE_BAD_CONTENT_ENCODING,    # 61 - Unrecognized/bad encoding
    CURLE_OBSOLETE62,              # 62 - NOT IN USE since 7.82.0
    CURLE_FILESIZE_EXCEEDED,       # 63 - Maximum file size exceeded
    CURLE_USE_SSL_FAILED,          # 64 - Requested FTP SSL level failed
    CURLE_SEND_FAIL_REWIND,        # 65 - Sending the data requires a rewind
                                   # that failed
    CURLE_SSL_ENGINE_INITFAILED,   # 66 - failed to initialise ENGINE
    CURLE_LOGIN_DENIED,            # 67 - user, password or similar was not
                                   # accepted and we failed to login
    CURLE_TFTP_NOTFOUND,           # 68 - file not found on server
    CURLE_TFTP_PERM,               # 69 - permission problem on server
    CURLE_REMOTE_DISK_FULL,        # 70 - out of disk space on server
    CURLE_TFTP_ILLEGAL,            # 71 - Illegal TFTP operation
    CURLE_TFTP_UNKNOWNID,          # 72 - Unknown transfer ID
    CURLE_REMOTE_FILE_EXISTS,      # 73 - File already exists
    CURLE_TFTP_NOSUCHUSER,         # 74 - No such user
    CURLE_CONV_FAILED,             # 75 - conversion failed
    CURLE_OBSOLETE76,              # 76 - NOT IN USE since 7.82.0
    CURLE_SSL_CACERT_BADFILE,      # 77 - could not load CACERT file, missing
                                   # or wrong format
    CURLE_REMOTE_FILE_NOT_FOUND,   # 78 - remote file not found
    CURLE_SSH,                     # 79 - error from the SSH layer, somewhat
                                   # generic so the error message will be of
                                   # interest when this has happened

    CURLE_SSL_SHUTDOWN_FAILED,     # 80 - Failed to shut down the SSL
                                   # connection
    CURLE_AGAIN,                   # 81 - socket is not ready for send/recv,
                                   # wait till it's ready and try again (Added
                                   # in 7.18.2)
    CURLE_SSL_CRL_BADFILE,         # 82 - could not load CRL file, missing or
                                   # wrong format (Added in 7.19.0)
    CURLE_SSL_ISSUER_ERROR,        # 83 - Issuer check failed.  (Added in
                                   # 7.19.0)
    CURLE_FTP_PRET_FAILED,         # 84 - a PRET command failed
    CURLE_RTSP_CSEQ_ERROR,         # 85 - mismatch of RTSP CSeq numbers
    CURLE_RTSP_SESSION_ERROR,      # 86 - mismatch of RTSP Session Ids
    CURLE_FTP_BAD_FILE_LIST,       # 87 - unable to parse FTP file list
    CURLE_CHUNK_FAILED,            # 88 - chunk callback reported error
    CURLE_NO_CONNECTION_AVAILABLE, # 89 - No connection available, the
                                   # session will be queued
    CURLE_SSL_PINNEDPUBKEYNOTMATCH, # 90 - specified pinned public key did not
                                   #  match
    CURLE_SSL_INVALIDCERTSTATUS,   # 91 - invalid certificate status
    CURLE_HTTP2_STREAM,            # 92 - stream error in HTTP/2 framing layer
    CURLE_RECURSIVE_API_CALL,      # 93 - an api function was called from
                                   # inside a callback
    CURLE_AUTH_ERROR,              # 94 - an authentication function returned an
                                   # error
    CURLE_HTTP3,                   # 95 - An HTTP/3 layer problem
    CURLE_QUIC_CONNECT_ERROR,      # 96 - QUIC connection error
    CURLE_PROXY,                   # 97 - proxy handshake error
    CURLE_SSL_CLIENTCERT,          # 98 - client-side certificate required
    CURLE_UNRECOVERABLE_POLL,      # 99 - poll/select returned fatal error
    CURL_LAST # never use!

  curl_ftpmethod* {.size: sizeof(clong).} = enum
    CURLFTPMETHOD_DEFAULT, # let libcurl pick
    CURLFTPMETHOD_MULTICWD, # single CWD operation for each path part
    CURLFTPMETHOD_NOCWD, # no CWD at all
    CURLFTPMETHOD_SINGLECWD, # one CWD to full dir, then work on file

  CURLMcode* {.size: sizeof(cint).} = enum
    CURLM_CALL_MULTI_PERFORM = -1, # please call curl_multi_perform() or
                                   #   curl_multi_socket*() soon
    CURLM_OK,
    CURLM_BAD_HANDLE,      # the passed-in handle is not a valid CURLM handle
    CURLM_BAD_EASY_HANDLE, # an easy handle was not good/valid
    CURLM_OUT_OF_MEMORY,   # if you ever get this, you're in deep sh*t
    CURLM_INTERNAL_ERROR,  # this is a libcurl bug
    CURLM_BAD_SOCKET,      # the passed in socket argument did not match
    CURLM_UNKNOWN_OPTION,  # curl_multi_setopt() with unsupported option
    CURLM_ADDED_ALREADY,   # an easy handle already added to a multi handle was
                           #   attempted to get added - again
    CURLM_RECURSIVE_API_CALL, # an api function was called from inside a
                              #   callback
    CURLM_WAKEUP_FAILURE,  # wakeup is unavailable or failed
    CURLM_BAD_FUNCTION_ARGUMENT, # function called with a bad parameter
    CURLM_ABORTED_BY_CALLBACK,
    CURLM_UNRECOVERABLE_POLL,
    CURLM_LAST

  CURLMSG_E* {.size: sizeof(cint).} = enum
    CURLMSG_NONE # first, not used
    CURLMSG_DONE # This easy handle has completed. 'result' contains
                 # the CURLcode of the transfer
    CURLMSG_LAST # last, not used

  CURLUcode* {.size: sizeof(cint).} = enum
    CURLUE_OK,
    CURLUE_BAD_HANDLE # 1
    CURLUE_BAD_PARTPOINTER # 2
    CURLUE_MALFORMED_INPUT # 3
    CURLUE_BAD_PORT_NUMBER # 4
    CURLUE_UNSUPPORTED_SCHEME # 5
    CURLUE_URLDECODE # 6
    CURLUE_OUT_OF_MEMORY # 7
    CURLUE_USER_NOT_ALLOWED # 8
    CURLUE_UNKNOWN_PART # 9
    CURLUE_NO_SCHEME # 10
    CURLUE_NO_USER # 11
    CURLUE_NO_PASSWORD # 12
    CURLUE_NO_OPTIONS # 13
    CURLUE_NO_HOST # 14
    CURLUE_NO_PORT # 15
    CURLUE_NO_QUERY # 16
    CURLUE_NO_FRAGMENT # 17
    CURLUE_NO_ZONEID # 18
    CURLUE_BAD_FILE_URL # 19
    CURLUE_BAD_FRAGMENT # 20
    CURLUE_BAD_HOSTNAME # 21
    CURLUE_BAD_IPV6 # 22
    CURLUE_BAD_LOGIN # 23
    CURLUE_BAD_PASSWORD # 24
    CURLUE_BAD_PATH # 25
    CURLUE_BAD_QUERY # 26
    CURLUE_BAD_SCHEME # 27
    CURLUE_BAD_SLASHES # 28
    CURLUE_BAD_USER # 29
    CURLUE_LACKS_IDN # 30
    CURLUE_LAST

  CURLUPart* {.size: sizeof(cint).} = enum
    CURLUPART_URL
    CURLUPART_SCHEME
    CURLUPART_USER
    CURLUPART_PASSWORD
    CURLUPART_OPTIONS
    CURLUPART_HOST
    CURLUPART_PORT
    CURLUPART_PATH
    CURLUPART_QUERY
    CURLUPART_FRAGMENT
    CURLUPART_ZONEID # added in 7.65.0

  curl_header* = object
    name*: cstring
    value*: cstring
    amount*: csize_t
    index*: csize_t
    origin*: cint
    anchor*: pointer

proc `==`*(a: CURL; b: CURL): bool {.borrow.}
proc `==`*(a: CURL; b: typeof(nil)): bool {.borrow.}
proc `==`*(a: CURLM; b: CURLM): bool {.borrow.}
proc `==`*(a: CURLM; b: typeof(nil)): bool {.borrow.}

{.push importc.}

proc curl_global_init*(flags: clong): CURLcode
proc curl_global_cleanup*()
proc curl_free*(p: pointer)

proc curl_easy_init*(): CURL
proc curl_easy_cleanup*(handle: CURL)
proc curl_easy_setopt*(handle: CURL; option: CURLoption): CURLcode {.varargs.}
proc curl_easy_perform*(handle: CURL): CURLcode
proc curl_easy_getinfo*(handle: CURL; info: CURLINFO): CURLcode {.varargs.}
proc curl_easy_strerror*(errornum: CURLcode): cstring
proc curl_easy_nextheader*(curl: CURL; origin: cuint; request: cint;
  prev: ptr curl_header): ptr curl_header
proc curl_easy_header*(curl: CURL; name: cstring; index: csize_t; origin: cuint;
  request: cint; hout: var ptr curl_header): cint

proc curl_url*(): CURLU
proc curl_url_cleanup*(handle: CURLU)
proc curl_url_dup*(inh: CURLU): CURLU
proc curl_url_get*(handle: CURLU; what: CURLUPart; part: ptr cstring;
  flags: cuint): CURLUcode
proc curl_url_set*(handle: CURLU; what: CURLUPart; part: cstring;
  flags: cuint): CURLUcode
proc curl_url_strerror*(code: CURLUcode): cstring

proc curl_mime_init*(handle: CURL): curl_mime
proc curl_mime_free*(mime: curl_mime)
proc curl_mime_addpart*(mime: curl_mime): curl_mimepart
proc curl_mime_name*(part: curl_mimepart; name: cstring)
proc curl_mime_data*(part: curl_mimepart; data: pointer; datasize: csize_t)
proc curl_mime_filename*(part: curl_mimepart; name: cstring)
proc curl_mime_filedata*(part: curl_mimepart; filename: cstring)

proc curl_slist_append*(slist: curl_slist; str: cstring): curl_slist
proc curl_slist_free_all*(slist: curl_slist)

proc curl_multi_init*(): CURLM
proc curl_multi_add_handle*(multi_handle: CURLM; curl_handle: CURL): CURLMcode
proc curl_multi_remove_handle*(multi_handle: CURLM; curl_handle: CURL): CURLMcode
proc curl_multi_fdset*(multi_handle: CURLM; read_fd_set, write_fd_set,
  exc_fd_set: pointer; max_fd: ptr cint): CURLMcode
proc curl_multi_wait*(multi_handle: CURLM; extra_fds: ptr curl_waitfd;
  extra_nfds: cuint; timeout_ns: cint; ret: ptr cint): CURLMcode
proc curl_multi_poll*(multi_handle: CURLM; extra_fds: ptr curl_waitfd;
  extra_nfds: cuint; timeout_ns: cint; ret: ptr cint): CURLMcode
proc curl_multi_wakeup*(multi_handle: CURLM): CURLMcode
proc curl_multi_perform*(multi_handle: CURLM; running_handles: ptr cint):
  CURLMcode
proc curl_multi_cleanup*(multi_handle: CURLM): CURLMcode
proc curl_multi_info_read*(multi_handle: CURLM; msgs_in_queue: ptr cint): CURLMsg
proc curl_multi_strerror*(code: CURLMcode): cstring
{.pop.}

{.pop.}


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
  of CURLE_URL_MALFORMAT: "InvalidURL"
  of CURLE_COULDNT_CONNECT: "ConnectionRefused"
  of CURLE_COULDNT_RESOLVE_PROXY: "FailedToResolveProxy"
  of CURLE_COULDNT_RESOLVE_HOST: "FailedToResolveHost"
  of CURLE_PROXY: "ProxyRefusedToConnect"
  else: "InternalError"

proc getCurlConnectionError(res: CURLcode): string =
  let e = curlErrorToChaError(res)
  let msg = $curl_easy_strerror(res)
  return "Cha-Control: ConnectionError " & e & " " & msg & "\n"

type
  EarlyHintState = enum
    ehsNone, ehsStarted, ehsDone

  HttpHandle = ref object
    curl: CURL
    statusline: bool
    connectreport: bool
    earlyhint: EarlyHintState
    slist: curl_slist

const STDIN_FILENO = 0
const STDOUT_FILENO = 1

proc writeAll(data: pointer; size: int) =
  var n = 0
  while n < size:
    let i = write(STDOUT_FILENO, addr cast[ptr UncheckedArray[uint8]](data)[n],
      int(size) - n)
    assert i >= 0
    n += i

proc puts(s: string) =
  if s.len > 0:
    writeAll(unsafeAddr s[0], s.len)

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
      puts("Status: " & $status & "\nCha-Control: ControlDone\n")
    return nitems
  if line == "\r\n" or line == "\n":
    # empty line (last, before body)
    if op.earlyhint == ehsStarted:
      # ignore; we do not have a way to stream headers yet.
      op.earlyhint = ehsDone
      # reset statusline; we are awaiting the next line.
      op.statusline = false
      return nitems
    puts("\r\n")
    return nitems

  if op.earlyhint != ehsStarted:
    # Regrettably, we can only write early hint headers after the status
    # code is already known.
    # For now, it seems easiest to just ignore them all.
    puts(line)
  return nitems

# From the documentation: size is always 1.
proc curlWriteBody(p: cstring; size, nmemb: csize_t; userdata: pointer):
    csize_t {.cdecl.} =
  return csize_t(write(STDOUT_FILENO, p, int(nmemb)))

# From the documentation: size is always 1.
proc readFromStdin(p: pointer; size, nitems: csize_t; userdata: pointer):
    csize_t {.cdecl.} =
  return csize_t(read(STDIN_FILENO, p, int(nitems)))

proc curlPreRequest(clientp: pointer; conn_primary_ip, conn_local_ip: cstring;
    conn_primary_port, conn_local_port: cint): cint {.cdecl.} =
  let op = cast[HttpHandle](clientp)
  op.connectreport = true
  puts("Cha-Control: Connected\n")
  return 0 # ok

func startsWithIgnoreCase(s1, s2: openArray[char]): bool =
  if s1.len < s2.len: return false
  for i in 0 ..< s2.len:
    if s1[i].toLowerAscii() != s2[i].toLowerAscii():
      return false
  return true

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
  let op = HttpHandle(curl: curl)
  curl.setopt(CURLOPT_SUPPRESS_CONNECT_HEADERS, 1)
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
  else: discard
  let headers = getEnv("REQUEST_HEADERS")
  for line in headers.split("\r\n"):
    const needle = "Accept-Encoding: "
    if line.startsWithIgnoreCase(needle):
      let s = line.substr(needle.len)
      # From the CURLOPT_ACCEPT_ENCODING manpage:
      # > The application does not have to keep the string around after
      # > setting this option.
      curl.setopt(CURLOPT_ACCEPT_ENCODING, cstring(s))
    # This is OK, because curl_slist_append strdup's line.
    op.slist = curl_slist_append(op.slist, cstring(line))
  if op.slist != nil:
    curl.setopt(CURLOPT_HTTPHEADER, op.slist)
  let res = curl_easy_perform(curl)
  if res != CURLE_OK and not op.connectreport:
    puts(getCurlConnectionError(res))
    op.connectreport = true
  curl_easy_cleanup(curl)

main()
