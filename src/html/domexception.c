#include <stdarg.h>
#include <stdio.h>

#include "qjs/quickjs.h"

#define COUNTOF(x) (sizeof(x) / sizeof(*(x)))

typedef struct JSDOMExceptionData {
    JSValue name;
    JSValue message;
    int code;
} JSDOMExceptionData;

typedef struct JSDOMExceptionNameDef {
    const char * const name;
    const char * const code_name;
} JSDOMExceptionNameDef;

static const JSDOMExceptionNameDef js_dom_exception_names_table[] = {
    { "IndexSizeError", "INDEX_SIZE_ERR" },
    { NULL, "DOMSTRING_SIZE_ERR" },
    { "HierarchyRequestError", "HIERARCHY_REQUEST_ERR" },
    { "WrongDocumentError", "WRONG_DOCUMENT_ERR" },
    { "InvalidCharacterError", "INVALID_CHARACTER_ERR" },
    { NULL, "NO_DATA_ALLOWED_ERR" },
    { "NoModificationAllowedError", "NO_MODIFICATION_ALLOWED_ERR" },
    { "NotFoundError", "NOT_FOUND_ERR" },
    { "NotSupportedError", "NOT_SUPPORTED_ERR" },
    { "InUseAttributeError", "INUSE_ATTRIBUTE_ERR" },
    { "InvalidStateError", "INVALID_STATE_ERR" },
    { "SyntaxError", "SYNTAX_ERR" },
    { "InvalidModificationError", "INVALID_MODIFICATION_ERR" },
    { "NamespaceError", "NAMESPACE_ERR" },
    { "InvalidAccessError", "INVALID_ACCESS_ERR" },
    { NULL, "VALIDATION_ERR" },
    { "TypeMismatchError", "TYPE_MISMATCH_ERR" },
    { "SecurityError", "SECURITY_ERR" },
    { "NetworkError", "NETWORK_ERR" },
    { "AbortError", "ABORT_ERR" },
    { "URLMismatchError", "URL_MISMATCH_ERR" },
    { "QuotaExceededError", "QUOTA_EXCEEDED_ERR" },
    { "TimeoutError", "TIMEOUT_ERR" },
    { "InvalidNodeTypeError", "INVALID_NODE_TYPE_ERR" },
    { "DataCloneError", "DATA_CLONE_ERR" }
};

static JSClassID js_class_dom_exception = 0;

static void js_domexception_finalizer(JSRuntime *rt, JSValue val)
{
    JSDOMExceptionData *s = JS_GetOpaque(val, js_class_dom_exception);
    if (s) {
        JS_FreeValueRT(rt, s->name);
        JS_FreeValueRT(rt, s->message);
        js_free_rt(rt, s);
    }
}

static void js_domexception_mark(JSRuntime *rt, JSValueConst val,
                                 JS_MarkFunc *mark_func)
{
    JSDOMExceptionData *s = JS_GetOpaque(val, js_class_dom_exception);
    if (s) {
        JS_MarkValue(rt, s->name, mark_func);
        JS_MarkValue(rt, s->message, mark_func);
    }
}

static JSValue js_domexception_constructor0(JSContext *ctx, JSValueConst new_target,
                                            int argc, JSValueConst *argv,
                                            int skip_first_level)
{
    JSDOMExceptionData *s;
    JSValue obj, message, name;

    obj = JS_NewObjectFromCtor(ctx, new_target, js_class_dom_exception);
    if (JS_IsException(obj))
        return JS_EXCEPTION;
    if (!JS_IsUndefined(argv[0]))
        message = JS_ToString(ctx, argv[0]);
    else
        message = JS_NewString(ctx, "");
    if (JS_IsException(message))
        goto fail1;
    if (!JS_IsUndefined(argv[1]))
        name = JS_ToString(ctx, argv[1]);
    else
        name = JS_NewString(ctx, "Error");
    if (JS_IsException(name))
        goto fail2;
    s = js_malloc(ctx, sizeof(*s));
    if (!s)
        goto fail3;
    s->name = name;
    s->message = message;
    s->code = -1;
    JS_SetOpaque(obj, s);
    JS_BuildBacktrace(ctx, obj, skip_first_level);
    return obj;
fail3:
    JS_FreeValue(ctx, name);
fail2:
    JS_FreeValue(ctx, message);
fail1:
    JS_FreeValue(ctx, obj);
    return JS_EXCEPTION;
}

static JSValue js_domexception_constructor(JSContext *ctx, JSValueConst new_target,
                                           int argc, JSValueConst *argv)
{
    return js_domexception_constructor0(ctx, new_target, argc, argv, 1);
}

static JSValue js_domexception_get_name(JSContext *ctx, JSValueConst this_val)
{
    JSDOMExceptionData *s;
    JSValue *valp;

    s = JS_GetOpaque2(ctx, this_val, js_class_dom_exception);
    if (!s)
        return JS_EXCEPTION;
    return JS_DupValue(ctx, s->name);
}

static JSValue js_domexception_get_message(JSContext *ctx,
                                           JSValueConst this_val)
{
    JSDOMExceptionData *s;

    s = JS_GetOpaque2(ctx, this_val, js_class_dom_exception);
    if (!s)
        return JS_EXCEPTION;
    return JS_DupValue(ctx, s->message);
}

static JSValue js_domexception_get_code(JSContext *ctx, JSValueConst this_val)
{
    JSDOMExceptionData *s;
    const char *name, *it;
    int i;
    size_t len;

    s = JS_GetOpaque2(ctx, this_val, js_class_dom_exception);
    if (!s)
        return JS_EXCEPTION;
    if (s->code == -1) {
        name = JS_ToCStringLen(ctx, &len, s->name);
        if (!name)
            return JS_EXCEPTION;
        for (i = 0; i < COUNTOF(js_dom_exception_names_table); i++) {
            it = js_dom_exception_names_table[i].name;
            if (it && !strcmp(it, name) && len == strlen(it)) {
                s->code = i;
                break;
            }
        }
        s->code++;
        JS_FreeCString(ctx, name);
    }
    return JS_NewInt32(ctx, s->code);
}

static const JSCFunctionListEntry js_domexception_proto_funcs[] = {
    JS_CGETSET_DEF("name", js_domexception_get_name, NULL ),
    JS_CGETSET_DEF("message", js_domexception_get_message, NULL ),
    JS_CGETSET_DEF("code", js_domexception_get_code, NULL ),
    JS_PROP_STRING_DEF("[Symbol.toStringTag]", "DOMException", JS_PROP_CONFIGURABLE ),
};

static const JSClassDef js_domexception_class_def = {
    "DOMException", js_domexception_finalizer, js_domexception_mark, NULL, NULL,
    NULL /* can_destroy */
};

JSValue JS_ThrowDOMException(JSContext *ctx, const char *name,
                             const char *fmt, ...)
{
    JSValue obj, js_name, js_message;
    JSValueConst argv[2];
    va_list ap;
    char buf[256];

    va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    js_name = JS_NewString(ctx, name);
    if (JS_IsException(js_name))
        return JS_EXCEPTION;
    js_message = JS_NewString(ctx, buf);
    if (JS_IsException(js_message)) {
        JS_FreeValue(ctx, js_name);
        return JS_EXCEPTION;
    }
    argv[0] = js_message;
    argv[1] = js_name;
    obj = js_domexception_constructor0(ctx, JS_UNDEFINED, 2, argv, 0);
    JS_FreeValue(ctx, js_message);
    JS_FreeValue(ctx, js_name);
    if (JS_IsException(obj))
        return JS_EXCEPTION;
    return JS_Throw(ctx, obj);
}

int JS_AddIntrinsicDOMException(JSContext *ctx)
{
    JSRuntime *rt = JS_GetRuntime(ctx);
    int i, res;
    JSAtom name;
    JSValue ctor, proto, global_obj;

    JS_NewClassID(&js_class_dom_exception);
    if (JS_NewClass(rt, js_class_dom_exception, &js_domexception_class_def) < 0)
        return -1;
    proto = JS_NewError(ctx);
    if (JS_IsException(proto))
        return -1;
    if (JS_SetPropertyFunctionList(ctx, proto, js_domexception_proto_funcs,
                                   COUNTOF(js_domexception_proto_funcs)) < 0)
        goto fail;
    ctor = JS_NewCFunction2(ctx, js_domexception_constructor, "DOMException", 2,
                            JS_CFUNC_constructor, 0);
    if (JS_IsException(ctor))
        goto fail;
    JS_SetConstructor(ctx, ctor, proto);
    for (i = 0; i < COUNTOF(js_dom_exception_names_table); i++) {
        name = JS_NewAtom(ctx, js_dom_exception_names_table[i].code_name);
        if ((JS_DefinePropertyValue(ctx, proto, name, JS_NewInt32(ctx, i + 1),
                                   JS_PROP_ENUMERABLE) < 0) ||
            (JS_DefinePropertyValue(ctx, ctor, name, JS_NewInt32(ctx, i + 1),
                                   JS_PROP_ENUMERABLE) < 0)) {
            JS_FreeValue(ctx, ctor);
            JS_FreeAtom(ctx, name);
            goto fail;
        }
        JS_FreeAtom(ctx, name);
    }
    global_obj = JS_GetGlobalObject(ctx);
    res = JS_DefinePropertyValueStr(ctx, global_obj, "DOMException", ctor,
                                    JS_PROP_WRITABLE | JS_PROP_CONFIGURABLE);
    JS_FreeValue(ctx, global_obj);
    if (res < 0)
        goto fail;
    JS_SetClassProto(ctx, js_class_dom_exception, proto);
    return 0;
fail:
    JS_FreeValue(ctx, proto);
    return -1;
}
