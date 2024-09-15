type ConnectErrorCode* = enum
  ERROR_CGI_CACHED_BODY_NOT_FOUND = (-18, "cached request body not found")
  ERROR_FAILED_TO_REDIRECT = (-17, "failed to redirect request body")
  ERROR_URL_NOT_IN_CACHE = (-16, "URL was not found in the cache")
  ERROR_FILE_NOT_IN_CACHE = (-15, "file was not found in the cache")
  ERROR_FAILED_TO_EXECUTE_CGI_SCRIPT = (-14, "failed to execute CGI script")
  ERROR_CGI_NO_DATA = (-13, "CGI script returned no data")
  ERROR_CGI_MALFORMED_HEADER = (-12, "CGI script returned a malformed header")
  ERROR_CGI_INVALID_CHA_CONTROL = (-11, "CGI got invalid Cha-Control header")
  ERROR_TOO_MANY_REWRITES = (-10, "too many URI method map rewrites")
  ERROR_INVALID_URI_METHOD_ENTRY = (-9, "invalid URI method entry")
  ERROR_CGI_FILE_NOT_FOUND = (-8, "CGI file not found")
  ERROR_INVALID_CGI_PATH = (-7, "invalid CGI path")
  ERROR_FAIL_SETUP_CGI = (-6, "failed to set up CGI script")
  ERROR_NO_CGI_DIR = (-5, "no local-CGI directory configured")
  ERROR_SOURCE_NOT_FOUND = (-4, "clone source could not be found")
  ERROR_LOADER_KILLED = (-3, "loader killed during transfer")
  ERROR_DISALLOWED_URL = (-2, "url not allowed by filter")
  ERROR_UNKNOWN_SCHEME = (-1, "unknown scheme")
  CONNECTION_SUCCESS = (0, "connection successful")
  ERROR_INTERNAL = (1, "internal error")
  ERROR_INVALID_METHOD = (2, "invalid method")
  ERROR_INVALID_URL = (3, "invalid URL")
  ERROR_FILE_NOT_FOUND = (4, "file not found")
  ERROR_CONNECTION_REFUSED = (5, "connection refused")
  ERROR_PROXY_REFUSED_TO_CONNECT = (6, "proxy refused to connect")
  ERROR_FAILED_TO_RESOLVE_HOST = (7, "failed to resolve host")
  ERROR_FAILED_TO_RESOLVE_PROXY = (8, "failed to resolve proxy")

converter toInt*(code: ConnectErrorCode): int =
  return int(code)

func getLoaderErrorMessage*(code: int): string =
  if code in int(ConnectErrorCode.low)..int(ConnectErrorCode.high):
    return $ConnectErrorCode(code)
  return "unexpected error code " & $code
