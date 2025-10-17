type ConnectionError* = enum
  ceLoaderGone = -19
  ceCookieStreamExists = -18
  ceCGICachedBodyUnavailable = -17
  ceCGIOutputHandleNotFound = -16
  ceCGIFailedToOpenCacheOutput = -15
  ceCGICachedBodyNotFound = -14
  ceFailedToRedirect = -13
  ceURLNotInCache = -12
  ceFileNotInCache = -11
  ceFailedToExecuteCGIScript = -10
  ceCGIMalformedHeader = -9
  ceCGIInvalidChaControl = -8
  ceTooManyRewrites = -7
  ceInvalidURIMethodEntry = -6
  ceCGIFileNotFound = -5
  ceInvalidCGIPath = -4
  ceFailedToSetUpCGI = -3
  ceDisallowedURL = -2
  ceUnknownScheme = -1
  ceNone = 0
  ceInternalError = (1, "InternalError")
  ceInvalidMethod = (2, "InvalidMethod")
  ceInvalidURL = (3, "InvalidURL")
  ceFileNotFound = (4, "FileNotFound")
  ceConnectionRefused = (5, "ConnectionRefused")
  ceProxyRefusedToConnect = (6, "ProxyRefusedToConnect")
  ceFailedToResolveHost = (7, "FailedToResolveHost")
  ceFailedToResolveProxy = (8, "FailedToResolveProxy")
  ceProxyAuthFail = (9, "ProxyAuthFail")
  ceInvalidResponse = (10, "InvalidResponse")
  ceProxyInvalidResponse = (11, "ProxyInvalidResponse")

const ErrorMessages* = [
  ceLoaderGone: "loader process crashed",
  ceCookieStreamExists: "cookie stream already exists",
  ceCGICachedBodyUnavailable: "request body is not ready in the cache",
  ceCGIOutputHandleNotFound: "request body output handle not found",
  ceCGIFailedToOpenCacheOutput: "failed to open cache output",
  ceCGICachedBodyNotFound: "cached request body not found",
  ceFailedToRedirect: "failed to redirect request body",
  ceURLNotInCache: "URL was not found in the cache",
  ceFileNotInCache: "file was not found in the cache",
  ceFailedToExecuteCGIScript: "failed to execute CGI script",
  ceCGIMalformedHeader: "CGI script returned a malformed header",
  ceCGIInvalidChaControl: "CGI got invalid Cha-Control header",
  ceTooManyRewrites: "too many URI method map rewrites",
  ceInvalidURIMethodEntry: "invalid URI method entry",
  ceCGIFileNotFound: "CGI file not found",
  ceInvalidCGIPath: "invalid CGI path",
  ceFailedToSetUpCGI: "failed to set up CGI script",
  ceDisallowedURL: "url not allowed by filter",
  ceUnknownScheme: "unknown scheme",
  ceNone: "connection successful",
  ceInternalError: "internal error",
  ceInvalidMethod: "invalid method",
  ceInvalidURL: "invalid URL",
  ceFileNotFound: "file not found",
  ceConnectionRefused: "connection refused",
  ceProxyRefusedToConnect: "proxy refused to connect",
  ceFailedToResolveHost: "failed to resolve host",
  ceFailedToResolveProxy: "failed to resolve proxy",
  ceProxyAuthFail: "proxy authentication failed",
  ceInvalidResponse: "received an invalid response",
  ceProxyInvalidResponse: "proxy returned an invalid response",
]

proc getLoaderErrorMessage*(code: int): string =
  if code in int(ConnectionError.low)..int(ConnectionError.high):
    return ErrorMessages[ConnectionError(code)]
  return "unexpected error code " & $code
