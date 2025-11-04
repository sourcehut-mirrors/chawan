{.push raises: [].}

from std/os import parentDir

import constcharp
import libregexp
import dtoa

export constcharp

export libregexp.JS_BOOL

{.passc: "-DNOT_LRE_ONLY".}

{.passl: "-lm".}

when not compileOption("threads"):
  const CFLAGS = "-fwrapv -DMNC_NO_THREADS"
else:
  const CFLAGS = "-fwrapv"
  {.passl: "-lpthread".}

{.compile("qjs/quickjs.c", CFLAGS).}

{.passc: "-I" & currentSourcePath().parentDir().}

const qjsheader = "qjs/quickjs.h"

const
  # all tags with a reference count are negative
  JS_TAG_FIRST* = -9 ## first negative tag
  JS_TAG_BIG_INT* = -9
  JS_TAG_SYMBOL* = -8
  JS_TAG_STRING* = -7
  JS_TAG_STRING_ROPE* = -6
  JS_TAG_MODULE* = -3 ## used internally
  JS_TAG_FUNCTION_BYTECODE* = -2 ## used internally
  JS_TAG_OBJECT* = -1
  JS_TAG_INT* = 0
  JS_TAG_BOOL* = 1
  JS_TAG_NULL* = 2
  JS_TAG_UNDEFINED* = 3
  JS_TAG_UNINITIALIZED* = 4
  JS_TAG_CATCH_OFFSET* = 5
  JS_TAG_EXCEPTION* = 6
  JS_TAG_SHORT_BIG_INT* = 7
  JS_TAG_FLOAT64* = 8 ##  any larger tag is FLOAT64 if JS_NAN_BOXING

when sizeof(int) < sizeof(int64):
  type JSValue* {.importc, header: qjsheader.} = distinct uint64

  type JSValueConst* {.importc: "JSValueConst".} = distinct JSValue

  template JS_VALUE_GET_TAG*(v: JSValueConst): int32 =
    cast[int32](cast[uint64](v) shr 32)

  template JS_VALUE_GET_PTR*(v: JSValueConst): pointer =
    cast[pointer](v)

  template JS_MKVAL*(t, val: untyped): JSValue =
    JSValue((cast[uint64](int64(t)) shl 32) or uint32(val))

  template JS_MKPTR*(t, p: untyped): JSValue =
    JSValue((cast[uint64](int64(t)) shl 32) or cast[uint](p))
else:
  type
    JSValueUnion* {.importc, header: qjsheader, union.} = object
      int32*: int32
      float64*: float64
      `ptr`*: pointer
    JSValue* {.importc, header: qjsheader.} = object
      u*: JSValueUnion
      tag*: int64

  type JSValueConst* {.importc: "JSValueConst".} = distinct JSValue

  template JS_VALUE_GET_TAG*(v: JSValueConst): int32 =
    cast[int32](JSValue(v).tag)

  template JS_VALUE_GET_PTR*(v: JSValueConst): pointer =
    cast[pointer](JSValue(v).u)

  template JS_MKVAL*(t, val: untyped): JSValue =
    JSValue(u: JSValueUnion(`int32`: val), tag: t)

  template JS_MKPTR*(t, p: untyped): JSValue =
    JSValue(u: JSValueUnion(`ptr`: p), tag: t)

type
  JSValueArray* = ptr UncheckedArray[JSValue]
  JSValueConstArray* = ptr UncheckedArray[JSValueConst]

  JSRuntimeT {.importc: "JSRuntime", header: qjsheader,
    incompleteStruct.} = object
  JSContextT {.importc: "JSContext", header: qjsheader,
    incompleteStruct.} = object
  JSModuleDefT {.importc: "JSModuleDef", header: qjsheader,
    incompleteStruct.} = object

  JSRuntime* = ptr JSRuntimeT
  JSContext* = ptr JSContextT
  JSModuleDef* = ptr JSModuleDefT
  JSCFunction* = proc(ctx: JSContext; this_val: JSValueConst; argc: cint;
      argv: JSValueConstArray): JSValue {.cdecl, raises: [].}
  JSCFunctionMagic* = proc(ctx: JSContext; this_val: JSValueConst; argc: cint;
      argv: JSValueConstArray; magic: cint): JSValue {.cdecl, raises: [].}
  JSCFunctionData* = proc(ctx: JSContext; this_val: JSValueConst; argc: cint;
    argv: JSValueConstArray; magic: cint;
    func_data: JSValueConstArray): JSValue {.cdecl, raises: [].}
  JSGetterFunction* = proc(ctx: JSContext; this_val: JSValueConst): JSValue
    {.cdecl, raises: [].}
  JSSetterFunction* = proc(ctx: JSContext; this_val, val: JSValueConst):
    JSValue {.cdecl, raises: [].}
  JSGetterMagicFunction* = proc(ctx: JSContext; this_val: JSValueConst;
    magic: cint): JSValue {.cdecl, raises: [].}
  JSSetterMagicFunction* = proc(ctx: JSContext; this_val, val: JSValueConst;
    magic: cint): JSValue {.cdecl, raises: [].}
  JSIteratorNextFunction* = proc(ctx: JSContext; this_val: JSValueConst;
    argc: cint; argv: JSValueConstArray; pdone: ptr cint; magic: cint):
    JSValue {.cdecl, raises: [].}
  JSClassID* = uint32
  JSAtom* {.importc: "JSAtom".} = distinct uint32
  JSClassFinalizer* = proc(rt: JSRuntime; val: JSValueConst) {.
    cdecl, raises: [].}
  JSClassCheckDestroy* = proc(rt: JSRuntime; val: JSValueConst): JS_BOOL
    {.cdecl, raises: [].}
  JSClassGCMark* = proc(rt: JSRuntime; val: JSValueConst;
    mark_func: JS_MarkFunc) {.cdecl, raises: [].}
  JS_MarkFunc* = proc(rt: JSRuntime; gp: ptr JSGCObjectHeader) {.
    cdecl, raises: [].}
  JSModuleNormalizeFunc* = proc(ctx: JSContext; module_base_name,
    module_name: cstringConst; opaque: pointer): cstring {.cdecl, raises: [].}
  JSModuleLoaderFunc* = proc(ctx: JSContext; module_name: cstringConst,
    opaque: pointer): JSModuleDef {.cdecl.}
  JSJobFunc* = proc(ctx: JSContext; argc: cint;
    argv: JSValueConstArray): JSValue {.cdecl.}
  JSGCObjectHeader* {.importc, header: qjsheader.} = object
  JSFreeArrayBufferDataFunc* = proc(rt: JSRuntime; opaque, p: pointer) {.
    cdecl, raises: [].}

  JSPropertyDescriptor* {.importc, header: qjsheader.} = object
    flags*: cint
    value*: JSValue
    getter*: JSValue
    setter*: JSValue

  JSClassExoticMethods* {.importc, header: qjsheader.} =  object
    # Return -1 if exception (can only happen in case of Proxy object),
    # FALSE if the property does not exists, TRUE if it exists. If 1 is
    # returned, the property descriptor 'desc' is filled if != NULL.
    get_own_property*: proc(ctx: JSContext; desc: ptr JSPropertyDescriptor;
      obj: JSValueConst; prop: JSAtom): cint {.cdecl.}
    # '*ptab' should hold the '*plen' property keys. Return 0 if OK,
    # -1 if exception. The 'is_enumerable' field is ignored.
    get_own_property_names*: proc(ctx: JSContext;
      ptab: ptr ptr UncheckedArray[JSPropertyEnum]; plen: ptr uint32;
      obj: JSValueConst): cint {.cdecl.}
    # return < 0 if exception, or TRUE/FALSE
    delete_property*: proc(ctx: JSContext; obj: JSValueConst; prop: JSAtom):
      cint {.cdecl.}
    # return < 0 if exception or TRUE/FALSE
    define_own_property*: proc(ctx: JSContext; this_obj: JSValueConst;
      prop: JSAtom; val, getter, setter: JSValueConst; flags: cint): cint
      {.cdecl.}
    # The following methods can be emulated with the previous ones,
    # so they are usually not needed
    # return < 0 if exception or TRUE/FALSE
    has_property*: proc(ctx: JSContext; obj: JSValueConst; atom: JSAtom): cint
      {.cdecl.}
    get_property*: proc(ctx: JSContext; obj: JSValueConst; atom: JSAtom;
      receiver: JSValueConst): JSValue {.cdecl.}
    set_property*: proc(ctx: JSContext; obj: JSValueConst; atom: JSAtom;
      value, receiver: JSValueConst; flags: cint): cint {.cdecl.}
    # To get a consistent object behavior when get_prototype != NULL,
    # get_property, set_property and set_prototype must be != NULL
    # and the object must be created with a JS_NULL prototype.
    get_prototype*: proc(ctx: JSContext; obj: JSValueConst): JSValue {.cdecl.}
    # return < 0 if exception or TRUE/FALSE
    set_prototype*: proc(ctx: JSContext; obj, proto_val: JSValueConst): cint {.
      cdecl.}
    # return < 0 if exception or TRUE/FALSE
    is_extensible*: proc(ctx: JSContext; obj: JSValueConst): cint {.cdecl.}
    # return < 0 if exception or TRUE/FALSE
    prevent_extensions*: proc(ctx: JSContext; obj: JSValueConst): cint {.cdecl.}

  JSClassExoticMethodsConst* {.importc: "const JSClassExoticMethods *",
    header: qjsheader.} = ptr JSClassExoticMethods

  JSRuntimeCleanUpFunc* {.importc.} = proc(rt: JSRuntime) {.cdecl.}

  JSClassCallP* {.importc: "JSClassCall *".} =
    proc(ctx: JSContext; func_obj, this_val: JSValueConst; argc: cint;
      argv: JSValueConstArray; flags: cint): JSValue {.cdecl.}

  JSClassDef* {.importc, header: qjsheader.} = object
    class_name*: cstring # pure ASCII only!
    finalizer*: JSClassFinalizer
    gc_mark*: JSClassGCMark
    # if call != NULL, the object is a function. If (flags &
    # JS_CALL_FLAG_CONSTRUCTOR) != 0, the function is called as a constructor.
    # In this case, 'this_val' is new.target. A constructor call only happens
    # if the object constructor bit is set (see JS_SetConstructorBit()).
    call*: JSClassCallP
    exotic*: JSClassExoticMethodsConst
    can_destroy*: JSClassCheckDestroy

  JSClassDefConst* {.importc: "const JSClassDef *",
    header: qjsheader.} = ptr JSClassDef

  JSCFunctionEnum* {.size: sizeof(uint8).} = enum
    JS_CFUNC_generic, JS_CFUNC_generic_magic, JS_CFUNC_constructor,
    JS_CFUNC_constructor_magic, JS_CFUNC_constructor_or_func,
    JS_CFUNC_constructor_or_func_magic, JS_CFUNC_f_f, JS_CFUNC_f_f_f,
    JS_CFUNC_getter, JS_CFUNC_setter, JS_CFUNC_getter_magic,
    JS_CFUNC_setter_magic, JS_CFUNC_iterator_next

  JSCFunctionType* {.importc, union.} = object
    generic*: JSCFunction
    generic_magic*: JSCFunctionMagic
    constructor*: JSCFunction
    constructor_magic*: JSCFunctionMagic
    constructor_or_func*: JSCFunction
    # note: f_f, f_f_f omitted
    getter*: JSGetterFunction
    setter*: JSSetterFunction
    getter_magic*: JSGetterMagicFunction
    setter_magic*: JSSetterMagicFunction
    iterator_next*: JSIteratorNextFunction

  JSCFunctionListP* = ptr UncheckedArray[JSCFunctionListEntry]

  JSCFunctionListEntryFunc = object
    length*: uint8
    cproto*: JSCFunctionEnum
    cfunc*: JSCFunctionType

  JSCFunctionListEntryGetSet = object
    get*: JSCFunctionType
    set*: JSCFunctionType

  JSCFunctionListEntryAlias = object
    name: cstring
    base: cint

  JSCFunctionListEntryPropList = object
    tab: JSCFunctionListP
    len: cint

  JSCFunctionListEntryU* {.union.} = object
    `func`* {.importc: "func".}: JSCFunctionListEntryFunc
    getset: JSCFunctionListEntryGetSet
    alias: JSCFunctionListEntryAlias
    prop_list: JSCFunctionListEntryPropList
    str: cstring
    i32: int32
    i64: int64
    f64: cdouble

  JSCFunctionListEntry* {.importc.} = object
    name*: cstring # pure ASCII or UTF-8 encoded
    prop_flags*: uint8
    def_type*: uint8
    magic*: int16
    u* {.importc.}: JSCFunctionListEntryU

  JSPropertyEnum* {.importc.} = object
    is_enumerable*: JS_BOOL
    atom*: JSAtom

  JSMallocState* {.importc.} = object
    malloc_count: csize_t
    malloc_size: csize_t
    malloc_limit: csize_t
    opaque: pointer

  JSMallocStateP* = ptr JSMallocState

  JSMallocFunctions* {.importc.} = object
    js_malloc*: proc(s: JSMallocStateP; size: csize_t): pointer {.cdecl.}
    js_free*: proc(s: JSMallocStateP; p: pointer) {.cdecl.}
    js_realloc*: proc(s: JSMallocStateP; p: pointer; size: csize_t): pointer
      {.cdecl.}
    js_malloc_usable_size*: proc(p: pointer) {.cdecl.}

  JSSharedArrayBufferFunctions* {.importc.} = object
    sab_alloc*: proc(opaque: pointer; size: csize_t): pointer {.cdecl.}
    sab_free*: proc(opaque: pointer) {.cdecl.}
    sab_dup*: proc(opaque: pointer): pointer {.cdecl.}
    sab_opaque*: pointer

  JSPromiseStateEnum* {.size: sizeof(cint).} = enum
    JS_PROMISE_PENDING
    JS_PROMISE_FULFILLED
    JS_PROMISE_REJECTED

proc `==`*(a, b: JSValue): bool {.error.} =
  discard

proc `==`*(a, b: JSAtom): bool {.borrow.}

converter toJSValueConst*(val: JSValue): JSValueConst {.importc,
    header: "quickjs-aux.h".} =
  JSValueConst(val)

converter toJSValueConstArray*(val: JSValueArray): JSValueConstArray {.
    importc, header: "quickjs-aux.h".} =
  JSValueConstArray(val)

template JS_NULL*(): untyped = JS_MKVAL(JS_TAG_NULL, 0)
template JS_UNDEFINED*(): untyped = JS_MKVAL(JS_TAG_UNDEFINED, 0)
template JS_FALSE*(): untyped = JS_MKVAL(JS_TAG_BOOL, 0)
template JS_TRUE*(): untyped = JS_MKVAL(JS_TAG_BOOL, 1)
template JS_EXCEPTION*(): untyped = JS_MKVAL(JS_TAG_EXCEPTION, 0)
template JS_UNINITIALIZED*(): untyped = JS_MKVAL(JS_TAG_UNINITIALIZED, 0)

const
  JS_EVAL_TYPE_GLOBAL* = (0 shl 0) ## global code (default)
  JS_EVAL_TYPE_MODULE* = (1 shl 0) ## module code
  JS_EVAL_TYPE_DIRECT* = (2 shl 0) ## direct call (internal use)
  JS_EVAL_TYPE_INDIRECT* = (3 shl 0) ## indirect call (internal use)
  JS_EVAL_TYPE_MASK* = (3 shl 0)
  JS_EVAL_FLAG_STRICT* = (1 shl 3) ##  force 'strict' mode
  JS_EVAL_FLAG_COMPILE_ONLY* = (1 shl 5) ## compile but do not run.
  ## The result is an object with a JS_TAG_FUNCTION_BYTECODE or
  ## JS_TAG_MODULE tag.  It can be executed with JS_EvalFunction().
  JS_EVAL_FLAG_BACKTRACE_BARRIER* = (1 shl 6) ## allow top-level await in normal
  ## script.  JS_Eval() returns a promise.  Only allowed with
  ## JS_EVAL_TYPE_GLOBAL

const
  JS_DEF_CFUNC* = 0
  JS_DEF_CGETSET* = 1
  JS_DEF_CGETSET_MAGIC* = 2
  JS_DEF_PROP_STRING* = 3
  JS_DEF_PROP_INT32* = 4
  JS_DEF_PROP_INT64* = 5
  JS_DEF_PROP_DOUBLE* = 6
  JS_DEF_PROP_UNDEFINED* = 7
  JS_DEF_OBJECT* = 8
  JS_DEF_ALIAS* = 9
  JS_DEF_PROP_ATOM* = 10
  JS_DEF_PROP_BOOL* = 11

const
  JS_PROP_CONFIGURABLE* = (1 shl 0)
  JS_PROP_WRITABLE* = (1 shl 1)
  JS_PROP_ENUMERABLE* = (1 shl 2)
  JS_PROP_C_W_E* = (JS_PROP_CONFIGURABLE or JS_PROP_WRITABLE or
    JS_PROP_ENUMERABLE)
  JS_PROP_LENGTH* = (1 shl 3) # used internally in Arrays
  JS_PROP_TMASK* = (3 shl 4) # mask for NORMAL, GETSET, VARREF, AUTOINIT
  JS_PROP_NORMAL* = (0 shl 4)
  JS_PROP_GETSET* = (1 shl 4)
  JS_PROP_VARREF* = (2 shl 4) # used internally
  JS_PROP_AUTOINIT* = (3 shl 4) # used internally
  JS_PROP_THROW* = (1 shl 14)

# Flags for JS_DefineProperty
const
  JS_PROP_HAS_SHIFT* = cint(8)
  JS_PROP_HAS_CONFIGURABLE* = cint(1 shl 8)
  JS_PROP_HAS_WRITABLE* = cint(1 shl 9)
  JS_PROP_HAS_ENUMERABLE* = cint(1 shl 10)
  JS_PROP_HAS_GET* = cint(1 shl 11)
  JS_PROP_HAS_SET* = cint(1 shl 12)
  JS_PROP_HAS_VALUE* = cint(1 shl 13)

template JS_CFUNC_DEF*(n: string; len: uint8; func1: JSCFunction):
    JSCFunctionListEntry =
  JSCFunctionListEntry(name: cstring(n),
                       prop_flags: JS_PROP_WRITABLE or JS_PROP_CONFIGURABLE,
                       def_type: JS_DEF_CFUNC,
                       u: JSCFunctionListEntryU(
                         `func`: JSCFunctionListEntryFunc(
                           length: len,
                           cproto: JS_CFUNC_generic,
                           cfunc: JSCFunctionType(generic: func1))))

template JS_CFUNC_DEF_NOCONF*(n: string; len: uint8; func1: JSCFunction):
    JSCFunctionListEntry =
  JSCFunctionListEntry(name: cstring(n),
                       prop_flags: JS_PROP_ENUMERABLE,
                       def_type: JS_DEF_CFUNC,
                       u: JSCFunctionListEntryU(
                         `func`: JSCFunctionListEntryFunc(
                           length: len,
                           cproto: JS_CFUNC_generic,
                           cfunc: JSCFunctionType(generic: func1))))

template JS_CGETSET_DEF*(n: string; fgetter: JSGetterFunction;
    fsetter: JSSetterFunction): JSCFunctionListEntry =
  JSCFunctionListEntry(name: cstring(n),
                       prop_flags: JS_PROP_CONFIGURABLE,
                       def_type: JS_DEF_CGETSET,
                       u: JSCFunctionListEntryU(
                         getset: JSCFunctionListEntryGetSet(
                           get: JSCFunctionType(getter: fgetter),
                           set: JSCFunctionType(setter: fsetter))))

template JS_CGETSET_DEF_NOCONF*(n: string; fgetter: JSGetterFunction;
    fsetter: JSSetterFunction): JSCFunctionListEntry =
  JSCFunctionListEntry(name: cstring(n),
                       prop_flags: JS_PROP_ENUMERABLE,
                       def_type: JS_DEF_CGETSET,
                       u: JSCFunctionListEntryU(
                         getset: JSCFunctionListEntryGetSet(
                           get: JSCFunctionType(getter: fgetter),
                           set: JSCFunctionType(setter: fsetter))))

template JS_CGETSET_MAGIC_DEF*(n: cstring; fgetter, fsetter: typed;
    m: int16): JSCFunctionListEntry =
  JSCFunctionListEntry(name: n,
                       prop_flags: JS_PROP_CONFIGURABLE,
                       def_type: JS_DEF_CGETSET_MAGIC,
                       magic: m,
                       u: JSCFunctionListEntryU(
                         getset: JSCFunctionListEntryGetSet(
                           get: JSCFunctionType(getter_magic: fgetter),
                           set: JSCFunctionType(setter_magic: fsetter))))

template JS_PROP_STRING_DEF*(n, cstr: cstring; f: cint):
    JSCFunctionListEntry =
  JSCFunctionListEntry(name: n,
                       prop_flags: f,
                       def_type: JS_DEF_PROP_STRING,
                       magic: 0,
                       u: JSCFunctionListEntryU(str: cstr))

{.push header: qjsheader, importc.}

proc JS_NewRuntime*(): JSRuntime
proc JS_SetRuntimeInfo*(rt: JSRuntime; info: cstringConst) ##
  ## info lifetime must
  ## exceed that of rt
proc JS_GetGCThreshold*(rt: JSRuntime): csize_t
proc JS_SetGCThreshold*(rt: JSRuntime; gc_threshold: csize_t)
proc JS_SetMaxStackSize*(rt: JSRuntime; stack_size: csize_t) ##
  ## use 0 to disable
  ## maximum stack check
proc JS_UpdateStackTop*(rt: JSRuntime) ##
  ## should be called when changing thread to update the stack top value
  ## used to check stack overflow.
proc JS_NewRuntime2*(mf: ptr JSMallocFunctions; opaque: pointer): JSRuntime
proc JS_FreeRuntime*(rt: JSRuntime)
proc JS_GetRuntimeOpaque*(rt: JSRuntime): pointer
proc JS_SetRuntimeOpaque*(rt: JSRuntime; p: pointer)
proc JS_SetRuntimeCleanUpFunc*(rt: JSRuntime;
  cleanup_func: JSRuntimeCleanUpFunc)
proc JS_UnsetCanDestroyHooks*(rt: JSRuntime)
proc JS_MarkValue*(rt: JSRuntime; val: JSValueConst; mark_func: JS_MarkFunc)
proc JS_RunGC*(rt: JSRuntime)
proc JS_IsLiveObject*(rt: JSRuntime; obj: JSValueConst): JS_BOOL

proc JS_NewContext*(rt: JSRuntime): JSContext
proc JS_FreeContext*(ctx: JSContext)
proc JS_DupContext*(ctx: JSContext): JSContext
proc JS_SetContextOpaque*(ctx: JSContext; opaque: pointer)
proc JS_GetContextOpaque*(ctx: JSContext): pointer
proc JS_GetRuntime*(ctx: JSContext): JSRuntime
proc JS_SetClassProto*(ctx: JSContext; class_id: JSClassID; obj: JSValue)
proc JS_GetClassProto*(ctx: JSContext; class_id: JSClassID): JSValue

# the following functions are used to select the intrinsic object to save memory
proc JS_NewContextRaw*(rt: JSRuntime): JSContext
proc JS_AddIntrinsicBaseObjects*(ctx: JSContext): cint
proc JS_AddIntrinsicDate*(ctx: JSContext): cint
proc JS_AddIntrinsicEval*(ctx: JSContext): cint
proc JS_AddIntrinsicStringNormalize*(ctx: JSContext): cint
proc JS_AddIntrinsicRegExpCompiler*(ctx: JSContext)
proc JS_AddIntrinsicRegExp*(ctx: JSContext): cint
proc JS_AddIntrinsicJSON*(ctx: JSContext): cint
proc JS_AddIntrinsicProxy*(ctx: JSContext): cint
proc JS_AddIntrinsicMapSet*(ctx: JSContext): cint
proc JS_AddIntrinsicTypedArrays*(ctx: JSContext): cint
proc JS_AddIntrinsicPromise*(ctx: JSContext): cint
proc JS_AddIntrinsicWeakRef*(ctx: JSContext): cint
proc JS_AddIntrinsicDOMException*(ctx: JSContext): cint

proc js_string_codePointRange*(ctx: JSContext; this_val: JSValueConst;
  argc: cint; argv: JSValueConstArray): JSValue

proc js_malloc_rt*(rt: JSRuntime; size: csize_t): pointer
proc js_free_rt*(rt: JSRuntime; p: pointer)
proc js_realloc_rt*(rt: JSRuntime; p: pointer; size: csize_t): pointer
proc js_malloc_usable_size_rt*(rt: JSRuntime; p: pointer): csize_t
proc js_mallocz_rt*(rt: JSRuntime; size: csize_t): pointer

proc js_malloc*(ctx: JSContext; size: csize_t): pointer
proc js_free*(ctx: JSContext; p: pointer)
proc js_realloc*(ctx: JSContext; p: pointer; size: csize_t): pointer
proc js_malloc_usable_size*(ctx: JSContext; p: pointer): csize_t
proc js_realloc2*(ctx: JSContext; p: pointer; size: csize_t;
  pslack: ptr csize_t): pointer
proc js_mallocz*(ctx: JSContext; size: csize_t): pointer
proc js_strdup*(ctx: JSContext; str: cstringConst): cstring
proc js_strndup*(ctx: JSContext; str: cstringConst; n: csize_t): cstring

type JSMemoryUsage* {.importc, header: qjsheader.} = object
  malloc_size*, malloc_limit*, memory_used_size*: int64
  malloc_count*: int64
  memory_used_count*: int64
  atom_count*, atom_size*: int64
  str_count*, str_size*: int64
  obj_count*, obj_size*: int64
  prop_count*, prop_size*: int64
  shape_count*, shape_size*: int64
  js_func_count*, js_func_size*, js_func_code_size*: int64
  js_func_pc2line_count*, js_func_pc2line_size*: int64
  c_func_count*, array_count*: int64
  fast_array_count*, fast_array_elements*: int64
  binary_object_count*, binary_object_size*: int64

proc JS_ComputeMemoryUsage*(rt: JSRuntime; s: var JSMemoryUsage)
proc JS_DumpMemoryUsage*(fp: File; s: var JSMemoryUsage; rt: JSRuntime)

# atom support
const JS_ATOM_NULL* = JSAtom(0)

proc JS_NewAtomLen*(ctx: JSContext; str: cstringConst; len: csize_t): JSAtom
proc JS_NewAtom*(ctx: JSContext; str: cstringConst): JSAtom
proc JS_NewAtomUInt32*(ctx: JSContext; u: uint32): JSAtom
proc JS_DupAtom*(ctx: JSContext; v: JSAtom): JSAtom
proc JS_FreeAtom*(ctx: JSContext; atom: JSAtom)
proc JS_FreeAtomRT*(rt: JSRuntime; atom: JSAtom)
proc JS_AtomToValue*(ctx: JSContext; atom: JSAtom): JSValue
proc JS_AtomToString*(ctx: JSContext; atom: JSAtom): JSValue
proc JS_AtomToCStringLen*(ctx: JSContext; plen: ptr csize_t; atom: JSAtom):
  cstringConst
proc JS_AtomToCString*(ctx: JSContext; atom: JSAtom): cstringConst
proc JS_ValueToAtom*(ctx: JSContext; val: JSValueConst): JSAtom

# object class support
const JS_INVALID_CLASS_ID* = JSClassID(0)

proc JS_NewClassID*(pclass_id: var JSClassID): JSClassID
proc JS_GetClassID*(obj: JSValueConst): JSClassID
proc JS_NewClass*(rt: JSRuntime; class_id: JSClassID;
  class_def: ptr JSClassDef): cint
proc JS_IsRegisteredClass*(rt: JSRuntime; class_id: JSClassID): cint

# value handling
proc JS_NewBool*(ctx: JSContext; val: JS_BOOL): JSValue
proc JS_NewInt32*(ctx: JSContext; val: int32): JSValue
proc JS_NewCatchOffset*(ctx: JSContext; val: int32): JSValue
proc JS_NewInt64*(ctx: JSContext; val: int64): JSValue
proc JS_NewUint32*(ctx: JSContext; val: uint32): JSValue
proc JS_NewNumber*(ctx: JSContext; val: cdouble): JSValue
proc JS_NewBigInt64*(ctx: JSContext; val: int64): JSValue
proc JS_NewBigUInt64*(ctx: JSContext; val: uint64): JSValue
proc JS_NewFloat64*(ctx: JSContext; val: cdouble): JSValue
proc JS_IsNumber*(v: JSValueConst): JS_BOOL
proc JS_IsBigInt*(v: JSValueConst): JS_BOOL
proc JS_IsBool*(v: JSValueConst): JS_BOOL
proc JS_IsNull*(v: JSValueConst): JS_BOOL
proc JS_IsUndefined*(v: JSValueConst): JS_BOOL
proc JS_IsException*(v: JSValueConst): JS_BOOL
proc JS_IsUninitialized*(v: JSValueConst): JS_BOOL
proc JS_IsString*(v: JSValueConst): JS_BOOL
proc JS_IsSymbol*(v: JSValueConst): JS_BOOL
proc JS_IsObject*(v: JSValueConst): JS_BOOL

proc JS_Throw*(ctx: JSContext; obj: JSValue): JSValue
proc JS_SetUncatchableException*(ctx: JSContext; flag: JS_BOOL)
proc JS_GetException*(ctx: JSContext): JSValue
proc JS_HasException*(ctx: JSContext): JS_BOOL
proc JS_IsError*(v: JSValueConst): JS_BOOL
proc JS_NewError*(ctx: JSContext): JSValue
proc JS_ThrowSyntaxError*(ctx: JSContext; fmt: cstring): JSValue {.varargs,
  discardable.}
proc JS_ThrowTypeError*(ctx: JSContext; fmt: cstring): JSValue {.varargs,
  discardable.}
proc JS_ThrowReferenceError*(ctx: JSContext; fmt: cstring): JSValue {.varargs,
  discardable.}
proc JS_ThrowRangeError*(ctx: JSContext; fmt: cstring): JSValue {.varargs,
  discardable.}
proc JS_ThrowInternalError*(ctx: JSContext; fmt: cstring): JSValue {.varargs,
  discardable.}
proc JS_ThrowDOMException*(ctx: JSContext; name, fmt: cstring): JSValue {.
  varargs, discardable.}
proc JS_ThrowOutOfMemory*(ctx: JSContext): JSValue {.discardable.}

proc JS_FreeValue*(ctx: JSContext; v: JSValue)
proc JS_FreeValueRT*(rt: JSRuntime; v: JSValue)
proc JS_DupValue*(ctx: JSContext; v: JSValueConst): JSValue
proc JS_DupValueRT*(rt: JSRuntime; v: JSValueConst): JSValue

proc JS_StrictEq*(ctx: JSContext; op1, op2: JSValueConst): JS_BOOL
proc JS_SameValue*(ctx: JSContext; op1, op2: JSValueConst): JS_BOOL
# Similar to same-value equality, but +0 and -0 are considered equal.
proc JS_SameValueZero*(ctx: JSContext; op1, op2: JSValueConst): JS_BOOL

# return -1 for JS_EXCEPTION
proc JS_ToBool*(ctx: JSContext; val: JSValueConst): cint
proc JS_ToInt32*(ctx: JSContext; pres: var int32; val: JSValueConst): cint
proc JS_ToUint32*(ctx: JSContext; pres: var uint32; val: JSValueConst): cint
proc JS_ToInt64*(ctx: JSContext; pres: var int64; val: JSValueConst): cint
proc JS_ToIndex*(ctx: JSContext; plen: var uint64; val: JSValueConst): cint
proc JS_ToFloat64*(ctx: JSContext; pres: var float64; val: JSValueConst): cint
# return an exception if 'val' is a Number
proc JS_ToBigInt64*(ctx: JSContext; pres: var int64; val: JSValueConst): cint
# same as JS_ToInt64 but allow BigInt
proc JS_ToInt64Ext*(ctx: JSContext; pres: var int64; val: JSValueConst): cint

proc JS_NewStringLen*(ctx: JSContext; str: cstringConst; len1: csize_t): JSValue
proc JS_NewString*(ctx: JSContext; str: cstring): JSValue
proc JS_NewAtomString*(ctx: JSContext; str: cstring): JSValue
proc JS_ToString*(ctx: JSContext; val: JSValueConst): JSValue
proc JS_ToPropertyKey*(ctx: JSContext; val: JSValueConst): JSValue
proc JS_ToCStringLen2*(ctx: JSContext; plen: var csize_t; val1: JSValueConst;
  cesu8: JS_BOOL): cstringConst
proc JS_ToCStringLen*(ctx: JSContext; plen: var csize_t; val1: JSValueConst):
  cstringConst
proc JS_ToCString*(ctx: JSContext; val1: JSValueConst): cstringConst
proc JS_FreeCString*(ctx: JSContext, p: cstringConst)

# Monoucha extensions - unstable API!
proc JS_NewNarrowStringLen*(ctx: JSContext; s: cstring; len: csize_t): JSValue
proc JS_IsStringWideChar*(str: JSValueConst): JS_BOOL
proc JS_GetNarrowStringBuffer*(str: JSValueConst): ptr UncheckedArray[uint8]
proc JS_GetStringLength*(str: JSValueConst): uint32

proc JS_NewObjectProtoClass*(ctx: JSContext; proto: JSValueConst;
  class_id: JSClassID): JSValue
proc JS_NewObjectClass*(ctx: JSContext; class_id: JSClassID): JSValue
proc JS_NewObjectProto*(ctx: JSContext; proto: JSValueConst): JSValue
proc JS_NewObject*(ctx: JSContext): JSValue

proc JS_IsFunction*(ctx: JSContext; val: JSValueConst): JS_BOOL
proc JS_IsConstructor*(ctx: JSContext; val: JSValueConst): JS_BOOL
proc JS_SetConstructorBit*(ctx: JSContext; func_obj: JSValueConst;
  val: JS_BOOL): JS_BOOL

# takes ownership of the values
proc JS_NewArrayFrom*(ctx: JSContext; count: cint; values: JSValueArray):
  JSValue
proc JS_NewArray*(ctx: JSContext): JSValue
proc JS_IsArray*(ctx: JSContext; v: JSValueConst): cint

proc JS_NewDate*(ctx: JSContext; epoch_ms: float64): JSValue

proc JS_GetProperty*(ctx: JSContext; this_obj: JSValueConst; prop: JSAtom):
  JSValue
proc JS_GetPropertyStr*(ctx: JSContext; this_obj: JSValueConst; prop: cstring):
  JSValue
proc JS_GetPropertyUint32*(ctx: JSContext; this_obj: JSValueConst; idx: uint32):
  JSValue

proc JS_SetProperty*(ctx: JSContext; this_obj: JSValueConst; prop: JSAtom;
  val: JSValue): cint
proc JS_SetPropertyUint32*(ctx: JSContext; this_obj: JSValueConst; idx: uint32;
  val: JSValue): cint
proc JS_SetPropertyInt64*(ctx: JSContext; this_obj: JSValueConst; idx: int64;
  val: JSValue): cint
proc JS_SetPropertyStr*(ctx: JSContext; this_obj: JSValueConst; prop: cstring;
  val: JSValue): cint
proc JS_HasProperty*(ctx: JSContext; this_obj: JSValueConst; prop: JSAtom): cint
proc JS_IsExtensible*(ctx: JSContext; obj: JSValueConst): cint
proc JS_PreventExtensions*(ctx: JSContext; obj: JSValueConst): cint
proc JS_DeleteProperty*(ctx: JSContext; obj: JSValueConst; prop: JSAtom;
  flags: cint): cint
proc JS_SetPrototype*(ctx: JSContext; obj, proto_val: JSValueConst): cint
proc JS_GetPrototype*(ctx: JSContext; val: JSValueConst): JSValue
proc JS_GetLength*(ctx: JSContext; obj: JSValueConst; pres: ptr uint64): JSValue
proc JS_SetLength*(ctx: JSContext; obj: JSValueConst; len: uint64): cint

const
  JS_GPN_STRING_MASK* = (1 shl 0)
  JS_GPN_SYMBOL_MASK* = (1 shl 1)
  JS_GPN_PRIVATE_MASK* = (1 shl 2)
  JS_GPN_ENUM_ONLY* = (1 shl 3)
  JS_GPN_SET_ENUM* = (1 shl 4)

proc JS_GetOwnPropertyNames*(ctx: JSContext;
  ptab: ptr ptr UncheckedArray[JSPropertyEnum]; plen: ptr uint32;
  obj: JSValueConst; flags: cint): cint
proc JS_GetOwnProperty*(ctx: JSContext; desc: ptr JSPropertyDescriptor;
  obj: JSValueConst; prop: JSAtom): cint
proc JS_FreePropertyEnum*(ctx: JSContext;
  tab: ptr UncheckedArray[JSPropertyEnum]; len: uint32)

proc JS_Call*(ctx: JSContext; func_obj, this_obj: JSValueConst; argc: cint;
  argv: JSValueConstArray): JSValue
# Monoucha extension - unstable API!
proc JS_NewObjectFromCtor*(ctx: JSContext; ctor: JSValueConst;
  class_id: JSClassID): JSValue
proc JS_Invoke*(ctx: JSContext; this_obj: JSValueConst; atom: JSAtom;
  argc: cint; argv: JSValueConstArray): JSValue
proc JS_CallConstructor*(ctx: JSContext; func_obj: JSValueConst; argc: cint;
  argv: JSValueConstArray): JSValue
proc JS_CallConstructor2*(ctx: JSContext; func_obj, new_target: JSValueConst;
  argc: cint; argv: JSValueConstArray): JSValue
proc JS_DetectModule*(input: cstringConst; input_len: csize_t): JS_BOOL
# 'input' must be zero terminated i.e. input[input_len] = '\0'.
proc JS_Eval*(ctx: JSContext; input: cstringConst; input_len: csize_t;
  filename: cstring; eval_flags: cint): JSValue
# same as JS_Eval() but with an explicit 'this_obj' parameter
proc JS_EvalThis*(ctx: JSContext; this_obj: JSValueConst; input: cstringConst;
  input_len: csize_t; filename: cstringConst; eval_flags: cint): JSValue
proc JS_GetGlobalObject*(ctx: JSContext): JSValue
proc JS_IsInstanceOf*(ctx: JSContext; val, obj: JSValueConst): cint
proc JS_DefineProperty*(ctx: JSContext; this_obj: JSValueConst; prop: JSAtom;
  val, getter, setter: JSValueConst; flags: cint): cint
proc JS_DefinePropertyValue*(ctx: JSContext; this_obj: JSValueConst;
  prop: JSAtom; val: JSValue; flags: cint): cint
proc JS_DefinePropertyValueUint32*(ctx: JSContext; this_obj: JSValueConst;
  idx: uint32; val: JSValue; flags: cint): cint
proc JS_DefinePropertyValueStr*(ctx: JSContext; this_obj: JSValueConst;
  prop: cstring; val: JSValue; flags: cint): cint
proc JS_DefinePropertyGetSet*(ctx: JSContext; this_obj: JSValueConst;
  prop: JSAtom; getter, setter: JSValue; flags: cint): cint
proc JS_SetOpaque*(obj: JSValueConst; opaque: pointer)
proc JS_GetOpaque*(obj: JSValueConst; class_id: JSClassID): pointer
proc JS_GetOpaque2*(ctx: JSContext; obj: JSValueConst; class_id: JSClassID):
  pointer
proc JS_GetAnyOpaque*(obj: JSValueConst; class_id: var JSClassID): pointer

# 'buf' must be zero terminated i.e. buf[buf_len] = '\0'.
proc JS_ParseJSON*(ctx: JSContext; buf: cstringConst; buf_len: csize_t;
  filename: cstringConst): JSValue
proc JS_JSONStringify*(ctx: JSContext; obj, replacer, space0: JSValueConst):
  JSValue
proc JS_NewArrayBuffer*(ctx: JSContext; buf: ptr UncheckedArray[uint8];
  len: csize_t; free_func: JSFreeArrayBufferDataFunc; opaque: pointer;
  is_shared: JS_BOOL): JSValue
proc JS_NewArrayBufferCopy*(ctx: JSContext; buf: ptr UncheckedArray[uint8];
  len: csize_t): JSValue
proc JS_DetachArrayBuffer*(ctx: JSContext; obj: JSValueConst)
proc JS_GetArrayBuffer*(ctx: JSContext; psize: var csize_t; obj: JSValueConst):
  ptr uint8

proc JS_IsArrayBuffer*(obj: JSValueConst): JS_BOOL
proc JS_GetUint8Array*(ctx: JSContext; psize: ptr csize_t; obj: JSValueConst):
  ptr UncheckedArray[uint8]

type JSTypedArrayEnum* {.size: sizeof(cint).} = enum
  JS_TYPED_ARRAY_UINT8C = 0
  JS_TYPED_ARRAY_INT8
  JS_TYPED_ARRAY_UINT8
  JS_TYPED_ARRAY_INT16
  JS_TYPED_ARRAY_UINT16
  JS_TYPED_ARRAY_INT32
  JS_TYPED_ARRAY_UINT32
  JS_TYPED_ARRAY_BIG_INT64
  JS_TYPED_ARRAY_BIG_UINT64
  JS_TYPED_ARRAY_FLOAT16
  JS_TYPED_ARRAY_FLOAT32
  JS_TYPED_ARRAY_FLOAT64

proc JS_NewTypedArray*(ctx: JSContext; argc: cint;
  argv: JSValueConstArray; array_type: JSTypedArrayEnum): JSValue
proc JS_GetTypedArrayBuffer*(ctx: JSContext; obj: JSValueConst;
  pbyte_offset, pbyte_length, pbytes_per_element: var csize_t): JSValue
proc JS_NewUint8Array*(ctx: JSContext; buf: ptr UncheckedArray[uint8];
  len: csize_t; free_func: JSFreeArrayBufferDataFunc; opaque: pointer;
  is_shared: JS_BOOL): JSValue
proc JS_GetTypedArrayType*(obj: JSValueConst): cint
proc JS_GetUint8Array*(ctx: JSContext; psize: var csize_t; obj: JSValueConst):
  JS_BOOL
proc JS_NewUint8ArrayCopy*(ctx: JSContext; buf: ptr UncheckedArray[uint8];
  len: csize_t): JSValue
proc JS_SetSharedArrayBufferFunctions*(rt: JSRuntime;
  sf: ptr JSSharedArrayBufferFunctions)

proc JS_NewPromiseCapability*(ctx: JSContext;
  resolving_funcs: JSValueArray): JSValue
proc JS_PromiseState*(ctx: JSContext; promise: JSValueConst): JSPromiseStateEnum
proc JS_PromiseResult*(ctx: JSContext; promise: JSValueConst): JSValue
proc JS_IsPromise*(val: JSValueConst): JS_BOOL

proc JS_NewSymbol*(ctx: JSContext; description: cstringConst;
  is_global: JS_BOOL): JSValue

# is_handled = TRUE means that the rejection is handled
type JSHostPromiseRejectionTracker =
  proc(ctx: JSContext; promise, reason: JSValueConst; is_handled: JS_BOOL;
    opaque: pointer) {.cdecl.}
proc JS_SetHostPromiseRejectionTracker*(rt: JSRuntime;
  cb: JSHostPromiseRejectionTracker; opaque: pointer)

# return != 0 if the JS code needs to be interrupted
type JSInterruptHandler* = proc(rt: JSRuntime; opaque: pointer): cint {.cdecl.}
proc JS_SetInterruptHandler*(rt: JSRuntime; cb: JSInterruptHandler;
  opaque: pointer)
# if can_block is TRUE, Atomics.wait() can be used
proc JS_SetCanBlock*(rt: JSRuntime; can_block: JS_BOOL)
# set the [IsHTMLDDA] internal slot
proc JS_SetIsHTMLDDA*(ctx: JSContext; obj: JSValueConst)

proc JS_SetModuleLoaderFunc*(rt: JSRuntime;
  module_normalize: JSModuleNormalizeFunc; module_loader: JSModuleLoaderFunc;
  opaque: pointer)
proc JS_GetImportMeta*(ctx: JSContext; m: JSModuleDef): JSValue
proc JS_GetModuleName*(ctx: JSContext; m: JSModuleDef): JSAtom
proc JS_GetModuleNamespace*(ctx: JSContext; m: JSModuleDef): JSValue

# JS Job support
proc JS_EnqueueJob*(ctx: JSContext; job_func: JSJobFunc; argc: cint;
  argv: JSValueConstArray): cint

proc JS_IsJobPending*(rt: JSRuntime): JS_BOOL
proc JS_ExecutePendingJob*(rt: JSRuntime; pctx: var JSContext): cint

type JSSABTab* {.importc.} = object
  tab*: ptr ptr UncheckedArray[uint8]
  len*: csize_t

# Object Writer/Reader (currently only used to handle precompiled code)
const
  JS_WRITE_OBJ_BYTECODE* = (1 shl 0) ## allow function/module
  JS_WRITE_OBJ_BSWAP* = 0 ## byte swapped output
  JS_WRITE_OBJ_SAB* = (1 shl 2) ## allow SharedArrayBuffer
  JS_WRITE_OBJ_REFERENCE* = (1 shl 3) ## allow object references to encode
                                      ## arbitrary object graph
proc JS_WriteObject*(ctx: JSContext; psize: ptr csize_t; obj: JSValueConst;
  flags: cint): ptr uint8
proc JS_WriteObject2*(ctx: JSContext; psize: ptr csize_t; obj: JSValueConst;
  flags: cint; psab_tab: ptr JSSABTab; psab_tab_len: ptr csize_t):
  ptr uint8

const
  JS_READ_OBJ_BYTECODE* = (1 shl 0) ## allow function/module
  JS_READ_OBJ_ROM_DATA* = 0 ## avoid duplicating 'buf' data
  JS_READ_OBJ_SAB* = (1 shl 2) ## allow SharedArrayBuffer
  JS_READ_OBJ_REFERENCE* = (1 shl 3) ## allow object references
proc JS_ReadObject*(ctx: JSContext; buf: ptr uint8; buf_len: csize_t;
  flags: cint): JSValue
proc JS_ReadObject2*(ctx: JSContext; buf: ptr uint8; buf_len: csize_t;
  flags: cint; psab_tab: ptr JSSABTab): JSValue
proc JS_EvalFunction*(ctx: JSContext; val: JSValue): JSValue ## instantiate
  ## and evaluate a bytecode function. Only used when reading a script or
  ## module with JS_ReadObject()
proc JS_ResolveModule*(ctx: JSContext; obj: JSValueConst): cint ## load the
  ## dependencies of the module 'obj'. Useful when JS_ReadObject() returns
  ## a module.

# only exported for os.Worker()
proc JS_GetScriptOrModuleName*(ctx: JSContext; n_stack_levels: cint): JSAtom
# only exported for os.Worker()
proc JS_LoadModule*(ctx: JSContext; basename, filename: cstringConst): JSValue

# C function definition
proc JS_NewCFunction2*(ctx: JSContext; cfunc: JSCFunction; name: cstring;
  length: cint; proto: JSCFunctionEnum; magic: cint): JSValue
proc JS_NewCFunction3*(ctx: JSContext; cfunc: JSCFunction; name: cstring;
  length: cint; proto: JSCFunctionEnum; magic: cint; proto_val: JSValueConst;
  n_fields: cint): JSValue
proc JS_NewCFunctionData*(ctx: JSContext; cfunc: JSCFunctionData;
  length, magic, data_len: cint; data: JSValueConstArray): JSValue
proc JS_NewCFunctionData2*(ctx: JSContext; cfunc: JSCFunctionData;
  name: cstring; length, magic, data_len: cint; data: JSValueConstArray):
  JSValue
proc JS_NewCFunction*(ctx: JSContext; cfunc: JSCFunction; name: cstring;
  length: cint): JSValue
proc JS_SetConstructor*(ctx: JSContext; func_obj, proto: JSValueConst)

# C property definition
proc JS_SetPropertyFunctionList*(ctx: JSContext; obj: JSValueConst;
  tab: JSCFunctionListP; len: cint): cint

# C module definition
type JSModuleInitFunc* = proc(ctx: JSContext; m: JSModuleDef): cint
proc JS_NewCModule*(ctx: JSContext; name_str: cstringConst;
  fun: JSModuleInitFunc): JSModuleDef
# can only be called before the module is instantiated
proc JS_AddModuleExport*(ctx: JSContext; m: JSModuleDef; name_str: cstringConst):
  cint
proc JS_AddModuleExportList*(ctx: JSContext; m: JSModuleDef;
  tab: JSCFunctionListP; len: cint): cint
# can only be called after the module is instantiated
proc JS_SetModuleExport*(ctx: JSContext; m: JSModuleDef;
  export_name: cstringConst; val: JSValue): cint
proc JS_SetModuleExportList*(ctx: JSContext; m: JSModuleDef;
  tab: JSCFunctionListP; len: cint): cint
proc JS_SetModulePrivateValue*(ctx: JSContext; m: JSModuleDef;
  val: JSValue): cint ## associate a JSValue to a C module
proc JS_GetModulePrivateValue*(ctx: JSContext; m: JSModuleDef): JSValue

{.pop.} # header, importc
{.pop.} # raises
