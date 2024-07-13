import std/posix

import lcgi

export lcgi, dynstream, twtstr

const libssl = staticExec("pkg-config --libs --silence-errors libssl libcrypto")

{.passc: libssl.}
{.passl: libssl.}

type
  ASN1_TIME* = pointer
  EVP_PKEY* = pointer
  EVP_MD_CTX* = pointer
  EVP_MD* = pointer
  ENGINE* = pointer

type
  SSL_CTX* {.importc, header: "<openssl/types.h>", incompleteStruct.} = object
  BIO* {.importc, header: "<openssl/types.h>", incompleteStruct.} = object
  SSL* {.importc, header: "<openssl/types.h>", incompleteStruct.} = object
  X509* {.importc, header: "<openssl/types.h>", incompleteStruct.} = object

{.push importc.}

let EVP_MAX_MD_SIZE* {.nodecl, header: "<openssl/evp.h>".}: cint

{.push cdecl.}
{.push header: "<openssl/err.h>".}
proc ERR_print_errors_fp*(fp: File)
{.pop.}

{.push header: "<openssl/x509.h>".}
proc X509_get0_pubkey*(x: ptr X509): EVP_PKEY
proc X509_get0_notAfter*(x: ptr X509): ASN1_TIME
proc X509_get0_notBefore*(x: ptr X509): ASN1_TIME
proc X509_cmp_current_time*(asn1_time: ASN1_TIME): cint

proc i2d_PUBKEY*(a: EVP_PKEY; pp: ptr ptr uint8): cint
{.pop.}

{.push header: "<openssl/evp.h>".}
proc EVP_MD_CTX_new*(): EVP_MD_CTX
proc EVP_MD_CTX_free*(ctx: EVP_MD_CTX)
proc EVP_DigestInit_ex*(ctx: EVP_MD_CTX; t: EVP_MD; impl: ENGINE): cint
proc EVP_DigestUpdate*(ctx: EVP_MD_CTX; d: pointer; cnt: csize_t): cint
proc EVP_DigestFinal_ex*(ctx: EVP_MD_CTX; md: ptr char; s: var cuint): cint

proc EVP_sha256*(): EVP_MD
{.pop.}

{.push header: "<openssl/asn1.h>".}
proc ASN1_TIME_to_tm*(s: ASN1_TIME; tm: ptr Tm): cint
{.pop.}

{.push header: "<openssl/bio.h>", header: "<openssl/ssl.h>".}
proc BIO_get_ssl*(b: ptr BIO; sslp: var ptr SSL): clong
proc BIO_new_ssl_connect*(ctx: ptr SSL_CTX): ptr BIO
proc BIO_do_handshake*(b: ptr BIO): clong
{.pop.}

{.push header: "<openssl/bio.h>".}
proc BIO_new_socket*(sock, close_flag: cint): ptr BIO
proc BIO_set_conn_hostname*(b: ptr BIO; name: cstring): clong
proc BIO_do_connect*(b: ptr BIO): clong
proc BIO_read*(b: ptr BIO; data: pointer; dlen: cint): cint
proc BIO_write*(b: ptr BIO; data: cstring; dlen: cint): cint

proc BIO_should_retry*(b: ptr BIO): cint
{.pop.}

{.push header: "<openssl/ssl.h>".}

type SSL_METHOD* {.incompleteStruct.} = object

let TLS1_2_VERSION* {.nodecl, header: "<openssl/ssl.h>"}: cint

proc SSL_CTX_new*(m: ptr SSL_METHOD): ptr SSL_CTX
proc SSL_CTX_free*(ctx: ptr SSL_CTX)
proc SSL_get_SSL_CTX*(ssl: ptr SSL): ptr SSL_CTX
proc SSL_new*(ctx: ptr SSL_CTX): ptr SSL
proc TLS_client_method*(): ptr SSL_METHOD
proc SSL_CTX_set_min_proto_version*(ctx: ptr SSL_CTX; version: cint): cint
proc SSL_CTX_set_cipher_list*(ctx: ptr SSL_CTX; str: cstring): cint
proc SSL_get0_peer_certificate*(ssl: ptr SSL): ptr X509
proc SSL_connect*(ssl: ptr SSL): cint
proc SSL_do_handshake*(ssl: ptr SSL): cint
proc SSL_set1_host*(ssl: ptr SSL; hostname: cstring): cint
proc SSL_read*(ssl: ptr SSL; buf: pointer; num: cint): cint
proc SSL_write*(ssl: ptr SSL; buf: pointer; num: cint): cint
proc SSL_set_fd*(ssl: ptr SSL; fd: cint): cint
proc SSL_shutdown*(ssl: ptr SSL): cint
proc SSL_free*(ssl: ptr SSL)

{.pop.} # <openssl/ssl.h>

{.pop.} # cdecl

{.pop.} # importc

proc connectSSLSocket*(os: PosixStream; host, port: string): ptr SSL =
  let ps = os.connectSocket(host, port)
  let ctx = SSL_CTX_new(TLS_client_method())
  if ctx.SSL_CTX_set_min_proto_version(TLS1_2_VERSION) == 0:
    os.die("InternalError", "failed to set min proto version")
  const preferredCiphers = "HIGH:!aNULL:!kRSA:!PSK:!SRP:!MD5:!RC4:!DSS"
  if ctx.SSL_CTX_set_cipher_list(preferredCiphers) == 0:
    os.die("InternalError", "failed to set cipher list")
  let ssl = SSL_new(ctx)
  if SSL_set_fd(ssl, ps.fd) == 0:
    os.die("InternalError", "failed to set SSL fd")
  return ssl

proc closeSSLSocket*(ssl: ptr SSL) =
  let ctx = SSL_get_SSL_CTX(ssl)
  discard SSL_shutdown(ssl)
  SSL_free(ssl)
  SSL_CTX_free(ctx)
