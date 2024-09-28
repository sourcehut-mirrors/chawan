type ConnectionError* = enum
  ceCGIOutputHandleNotFound = -17
  ceCGIFailedToOpenCacheOutput = -16
  ceCGICachedBodyNotFound = -15
  ceFailedToRedirect = -14
  ceURLNotInCache = -13
  ceFileNotInCache = -12
  ceFailedToExecuteCGIScript = -11
  ceCGIMalformedHeader = -10
  ceCGIInvalidChaControl = -9
  ceTooManyRewrites = -8
  ceInvalidURIMethodEntry = -7
  ceCGIFileNotFound = -6
  ceInvalidCGIPath = -5
  ceFailedToSetUpCGI = -4
  ceNoCGIDir = -3
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

const ErrorMessages* = [
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
  ceNoCGIDir: "no local-CGI directory configured",
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
]

converter toInt*(code: ConnectionError): int =
  return int(code)

func getLoaderErrorMessage*(code: int): string =
  if code in int(ConnectionError.low)..int(ConnectionError.high):
    return ErrorMessages[ConnectionError(code)]
  return "unexpected error code " & $code
