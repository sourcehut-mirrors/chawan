/*
 * Pseudo-printf for CoW strings.
 *
 * This pretty much works like printf, except the format string is
 * generated automagically with a macro so it's guaranteed to be safe
 * (barring implementation bugs of course).
 *
 * In principle this *could* all be done in the macro, but that would
 * imply inlining every string construction which bloats the binary
 * enormously.
 */

#include <stdarg.h>
#include <stdlib.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>

typedef struct cha_Growbuf cha_Growbuf;

#define DLE '\x10'

void cha_Growbuf_reserveAdd(cha_Growbuf *, size_t);
void cha_Growbuf_addC(cha_Growbuf *, char);
void cha_Growbuf_addSpan(cha_Growbuf *, char *, size_t);
void cha_Growbuf_addI32(cha_Growbuf *, int32_t);
void cha_Growbuf_addU32(cha_Growbuf *, uint32_t);
void cha_Growbuf_addI64(cha_Growbuf *, int64_t);
void cha_Growbuf_addU64(cha_Growbuf *, uint64_t);

void cha_Growbuf_addV(cha_Growbuf *buf, char *fmt, ...)
{
    char c, *p, *base;
    size_t len;
    va_list ap;
    uint64_t u;
    int is_signed;

    va_start(ap, fmt);
    /* measure length */
    len = 0;
    for (p = fmt; *p; p++) {
        if (*p != DLE) {
            len++;
            continue;
        }
        is_signed = 0;
        switch (*++p) {
        case 'S':
            len += va_arg(ap, size_t);
            (void)va_arg(ap, char *);
            break;
        case 's':
            base = va_arg(ap, char *);
            len += strlen(base);
            break;
        case 'c':
            c = va_arg(ap, int);
            len++;
            break;
        case 'I':
            is_signed = 1;
        case 'U':
            u = va_arg(ap, uint64_t);
            goto measure_int;
        case 'i':
            is_signed = 1;
        case 'u':
            u = va_arg(ap, uint32_t);
measure_int:
            if (is_signed && (int64_t)u < 0) {
                len++;
                u = 0 - u;
            }
            len += (u == 0);
            while (u) {
                len++;
                u /= 10;
            }
            break;
        default:
            goto invalid_args;
        }
        if ((ptrdiff_t)len < 0)
            goto overflow;
    }
    va_end(ap);
    cha_Growbuf_reserveAdd(buf, len);
    va_start(ap, fmt);
    for (p = fmt; *p; p++) {
        if (*p != DLE) {
            cha_Growbuf_addC(buf, *p);
            continue;
        }
        is_signed = 0;
        switch (*++p) {
        case 'S':
            len = va_arg(ap, size_t);
            base = va_arg(ap, char *);
            cha_Growbuf_addSpan(buf, base, len);
            break;
        case 's':
            base = va_arg(ap, char *);
            len = strlen(base);
            cha_Growbuf_addSpan(buf, base, len);
            break;
        case 'c':
            c = va_arg(ap, int);
            cha_Growbuf_addC(buf, c);
            break;
        case 'I':
            u = va_arg(ap, int64_t);
            cha_Growbuf_addI64(buf, u);
            break;
        case 'U':
            u = va_arg(ap, uint64_t);
            cha_Growbuf_addU64(buf, u);
            break;
        case 'i':
            u = va_arg(ap, int32_t);
            cha_Growbuf_addI32(buf, u);
            break;
        case 'u':
            u = va_arg(ap, uint32_t);
            cha_Growbuf_addU32(buf, u);
            break;
        }
    }
    va_end(ap);
    return;
overflow:
invalid_args:
    abort();
}
