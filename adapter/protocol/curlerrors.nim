import curl

func curlErrorToChaError*(res: CURLcode): string =
  return case res
  of CURLE_OK: ""
  of CURLE_URL_MALFORMAT: "InvalidURL" #TODO should never occur...
  of CURLE_COULDNT_CONNECT: "ConnectionRefused"
  of CURLE_COULDNT_RESOLVE_PROXY: "FailedToResolveProxy"
  of CURLE_COULDNT_RESOLVE_HOST: "FailedToResolveHost"
  of CURLE_PROXY: "ProxyRefusedToConnect"
  else: "InternalError"

proc getCurlConnectionError*(res: CURLcode): string =
  let e = curlErrorToChaError(res)
  let msg = $curl_easy_strerror(res)
  return "Cha-Control: ConnectionError " & e & " " & msg & "\n"
