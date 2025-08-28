import monoucha/fromjs
import monoucha/javascript
import monoucha/jserror
import monoucha/quickjs
import monoucha/tojs
import types/opt

const NamesTable = {
  "IndexSizeError": 1u16,
  "HierarchyRequestError": 3u16,
  "WrongDocumentError": 4u16,
  "InvalidCharacterError": 5u16,
  "NoModificationAllowedError": 7u16,
  "NotFoundError": 8u16,
  "NotSupportedError": 9u16,
  "InUseAttributeError": 10u16,
  "InvalidStateError": 11u16,
  "SyntaxError": 12u16,
  "InvalidModificationError": 13u16,
  "NamespaceError": 14u16,
  "InvalidAccessError": 15u16,
  "TypeMismatchError": 17u16,
  "SecurityError": 18u16,
  "NetworkError": 19u16,
  "AbortError": 20u16,
  "URLMismatchError": 21u16,
  "QuotaExceededError": 22u16,
  "TimeoutError": 23u16,
  "InvalidNodeTypeError": 24u16,
  "DataCloneError": 25u16
}

type
  DOMExceptionType = enum
    INDEX_SIZE_ERR = 1
    DOMSTRING_SIZE_ERR = 2
    HIERARCHY_REQUEST_ERR = 3
    WRONG_DOCUMENT_ERR = 4
    INVALID_CHARACTER_ERR = 5
    NO_DATA_ALLOWED_ERR = 6
    NO_MODIFICATION_ALLOWED_ERR = 7
    NOT_FOUND_ERR = 8
    NOT_SUPPORTED_ERR = 9
    INUSE_ATTRIBUTE_ERR = 10
    INVALID_STATE_ERR = 11
    SYNTAX_ERR = 12
    INVALID_MODIFICATION_ERR = 13
    NAMESPACE_ERR = 14
    INVALID_ACCESS_ERR = 15
    VALIDATION_ERR = 16
    TYPE_MISMATCH_ERR = 17
    SECURITY_ERR = 18
    NETWORK_ERR = 19
    ABORT_ERR = 20
    URL_MISMATCH_ERR = 21
    QUOTA_EXCEEDED_ERR = 22
    TIMEOUT_ERR = 23
    INVALID_NODE_TYPE_ERR = 24
    DATA_CLONE_ERR = 25

  DOMException* = ref object of JSError
    name* {.jsget.}: string
    code: int

  DOMResult*[T] = Result[T, DOMException]

jsDestructor(DOMException)

proc newDOMException*(message = ""; name = "Error"): DOMException {.jsctor.} =
  return DOMException(e: jeCustom, name: name, message: message, code: -1)

template errDOMException*(message, name: string): untyped =
  err(newDOMException(message, name))

proc JS_ThrowDOMException*(ctx: JSContext; message, name: string): JSValue =
  return JS_Throw(ctx, ctx.toJS(newDOMException(message, name)))

proc getMessage(this: DOMException): string {.jsfget: "message".} =
  return this.message

proc getCode(this: DOMException): uint16 {.jsfget: "code".} =
  if this.code == -1:
    this.code = 0
    for it in NamesTable:
      if it[0] == this.name:
        this.code = int(it[1])
        break
  return uint16(this.code)

proc addDOMExceptionModule*(ctx: JSContext) =
  let domExceptionCID = ctx.registerType(DOMException, JS_CLASS_ERROR)
  doAssert ctx.defineConsts(domExceptionCID, DOMExceptionType) == dprSuccess
