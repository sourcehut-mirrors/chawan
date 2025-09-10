{.push raises: [].}

import std/posix

import lcgi

export lcgi, dynstream, twtstr, sandbox

type
  ASN1_TIME* = pointer
  EVP_PKEY* = pointer
  EVP_MD_CTX* = pointer
  EVP_MD* = pointer
  ENGINE* = pointer
  X509_STORE_CTX* = pointer

type
  SSL_CTX* {.importc, header: "<openssl/ssl.h>", incompleteStruct.} = object
  BIO* {.importc, header: "<openssl/bio.h>", incompleteStruct.} = object
  SSL* {.importc, header: "<openssl/ssl.h>", incompleteStruct.} = object
  X509* {.importc, header: "<openssl/x509.h>", incompleteStruct.} = object

const
  SSL_VERIFY_NONE* = cint(0x00)
  SSL_VERIFY_PEER* = cint(0x01)
  SSL_VERIFY_FAIL_IF_NO_PEER_CERT* = cint(0x02)
  SSL_VERIFY_CLIENT_ONCE* = cint(0x04)
  SSL_VERIFY_POST_HANDSHAKE* = cint(0x08)

{.push importc.}

let EVP_MAX_MD_SIZE* {.nodecl, header: "<openssl/evp.h>".}: cint

{.push cdecl.}
{.push header: "<openssl/err.h>".}
proc ERR_print_errors_fp*(fp: ChaFile)
proc ERR_get_error(): culong
proc ERR_reason_error_string(e: culong): cstring
{.pop.}

{.push header: "<openssl/x509.h>".}
proc X509_get0_pubkey*(x: ptr X509): EVP_PKEY
proc X509_get0_notAfter*(x: ptr X509): ASN1_TIME
proc X509_get0_notBefore*(x: ptr X509): ASN1_TIME
proc X509_cmp_current_time*(asn1_time: ASN1_TIME): cint
proc X509_verify_cert_error_string*(n: clong): cstring
proc X509_free*(x: ptr X509)

proc i2d_PUBKEY*(a: EVP_PKEY; pp: ptr ptr uint8): cint
{.pop.}

{.push header: "<openssl/evp.h>".}
proc EVP_MD_CTX_new*(): EVP_MD_CTX
proc EVP_MD_CTX_free*(ctx: EVP_MD_CTX)
proc EVP_DigestInit_ex*(ctx: EVP_MD_CTX; t: EVP_MD; impl: ENGINE): cint
proc EVP_DigestUpdate*(ctx: EVP_MD_CTX; d: pointer; cnt: csize_t): cint
proc EVP_DigestFinal_ex*(ctx: EVP_MD_CTX; md: ptr uint8; s: var cuint): cint

proc EVP_sha256*(): EVP_MD
{.pop.}

{.push header: "<openssl/asn1.h>".}
proc ASN1_TIME_to_tm*(s: ASN1_TIME; tm: ptr Tm): cint
{.pop.}

{.push header: "<openssl/bio.h>".}
proc BIO_read*(b: ptr BIO; data: pointer; dlen: cint): cint
proc BIO_write*(b: ptr BIO; data: cstring; dlen: cint): cint

proc BIO_should_retry*(b: ptr BIO): cint
{.pop.}

{.push header: "<openssl/ssl.h>".}

type SSL_METHOD* {.incompleteStruct.} = object

let TLS1_2_VERSION* {.nodecl, header: "<openssl/ssl.h>"}: cint

type SSL_verify_cb* = proc(preverify_ok: cint; x509_ctx: X509_STORE_CTX): cint
  {.cdecl.}

const X509_V_OK* = clong(0)

proc SSL_CTX_new(m: ptr SSL_METHOD): ptr SSL_CTX
proc SSL_CTX_free(ctx: ptr SSL_CTX)
proc SSL_get_SSL_CTX(ssl: ptr SSL): ptr SSL_CTX
proc SSL_new(ctx: ptr SSL_CTX): ptr SSL
proc TLS_client_method(): ptr SSL_METHOD
proc SSL_CTX_set_min_proto_version(ctx: ptr SSL_CTX; version: cint): cint
proc SSL_CTX_set_cipher_list(ctx: ptr SSL_CTX; str: cstring): cint
proc SSL_CTX_set_default_verify_paths(ctx: ptr SSL_CTX): cint
proc SSL_CTX_set_verify*(ssl: ptr SSL_CTX; mode: cint;
  verify_callback: SSL_verify_cb)
proc SSL_set_tlsext_host_name(ssl: ptr SSL; name: cstring): cint
proc SSL_get_peer_certificate*(ssl: ptr SSL): ptr X509
proc SSL_get_verify_result*(ssl: ptr SSL): clong
proc SSL_connect(ssl: ptr SSL): cint
proc SSL_do_handshake(ssl: ptr SSL): cint
proc SSL_set1_host(ssl: ptr SSL; hostname: cstring): cint
proc SSL_read*(ssl: ptr SSL; buf: pointer; num: cint): cint
proc SSL_write*(ssl: ptr SSL; buf: pointer; num: cint): cint
proc SSL_set_fd(ssl: ptr SSL; fd: cint): cint
proc SSL_shutdown(ssl: ptr SSL): cint
proc SSL_free(ssl: ptr SSL)

{.pop.} # <openssl/ssl.h>

{.pop.} # cdecl

{.pop.} # importc

# WARNING: you must call SSL_get_verify_result on the returned SSL
# yourself.
proc connectSSLSocket*(host, port: string; useDefaultCA: bool):
    CGIResult[ptr SSL] =
  let ps = ?connectSocket(host, port)
  let ctx = SSL_CTX_new(TLS_client_method())
  if useDefaultCA:
    SSL_CTX_set_verify(ctx, SSL_VERIFY_NONE, nil)
    if SSL_CTX_set_default_verify_paths(ctx) == 0:
      return errCGIError(ceInternalError, "failed to set default verify paths")
  if ctx.SSL_CTX_set_min_proto_version(TLS1_2_VERSION) == 0:
    return errCGIError(ceInternalError, "failed to set min proto version")
  const preferredCiphers = "HIGH:!aNULL:!kRSA:!PSK:!SRP:!MD5:!RC4:!DSS:!DHE"
  if ctx.SSL_CTX_set_cipher_list(preferredCiphers) == 0:
    return errCGIError(ceInternalError, "failed to set cipher list")
  let ssl = SSL_new(ctx)
  if SSL_set_fd(ssl, ps.fd) != 1:
    return errCGIError(ceInternalError, "failed to set SSL fd")
  if SSL_set1_host(ssl, cstring(host)) == 0:
    return errCGIError(ceInternalError, "failed to set host")
  if SSL_set_tlsext_host_name(ssl, cstring(host)) == 0:
    return errCGIError(ceInternalError, "failed to set tlsext host name")
  if SSL_connect(ssl) <= 0:
    let e = ERR_get_error()
    return errCGIError(ceConnectionRefused, ERR_reason_error_string(e))
  if SSL_do_handshake(ssl) <= 0:
    let e = ERR_get_error()
    return errCGIError(ceConnectionRefused, ERR_reason_error_string(e))
  ok(ssl)

proc closeSSLSocket*(ssl: ptr SSL) =
  let ctx = SSL_get_SSL_CTX(ssl)
  discard SSL_shutdown(ssl)
  SSL_free(ssl)
  SSL_CTX_free(ctx)

type
  SSLStream* = ref object of DynStream
    ssl: ptr SSL

method readData*(s: SSLStream; buffer: pointer; len: int): int =
  return int(SSL_read(s.ssl, buffer, cint(len)))

method writeData*(s: SSLStream; buffer: pointer; len: int): int =
  return int(SSL_write(s.ssl, buffer, cint(len)))

method sclose*(s: SSLStream) =
  s.ssl.closeSSLSocket()

proc newSSLStream*(ssl: ptr SSL): SSLStream =
  return SSLStream(ssl: ssl)

{.pop.} # raises: []
