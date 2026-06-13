// ee_printf_min.c — minimal integer-only ee_printf for CoreMark (HAS_FLOAT=0).
// SPDX-License-Identifier: Apache-2.0
// Handles %d %u %x %X %c %s %% with optional 0-pad/width and the l/ll length
// modifier (CoreMark uses %lu and %04x). Output -> uart_send_char (core_portme.c).
#include <stdarg.h>

void uart_send_char(char c);

static void emit_str(const char *s) { while (*s) uart_send_char(*s++); }

static void emit_uint(unsigned long v, unsigned base, int upper, int width, int zero)
{
    char buf[24]; int n = 0;
    const char *dig = upper ? "0123456789ABCDEF" : "0123456789abcdef";
    if (v == 0) buf[n++] = '0';
    while (v) { buf[n++] = dig[v % base]; v /= base; }
    for (int pad = width - n; pad > 0; pad--) uart_send_char(zero ? '0' : ' ');
    while (n) uart_send_char(buf[--n]);
}

int ee_printf(const char *fmt, ...)
{
    va_list ap; va_start(ap, fmt);
    for (; *fmt; fmt++) {
        if (*fmt != '%') { uart_send_char(*fmt); continue; }
        fmt++;
        int zero = 0, width = 0, lng = 0;
        if (*fmt == '0') { zero = 1; fmt++; }
        while (*fmt >= '0' && *fmt <= '9') { width = width * 10 + (*fmt - '0'); fmt++; }
        while (*fmt == 'l') { lng++; fmt++; }
        switch (*fmt) {
            case 'd': {
                long v = lng ? va_arg(ap, long) : (long)va_arg(ap, int);
                if (v < 0) { uart_send_char('-'); v = -v; }
                emit_uint((unsigned long)v, 10, 0, width, zero);
            } break;
            case 'u': emit_uint(lng ? va_arg(ap, unsigned long) : (unsigned long)va_arg(ap, unsigned), 10, 0, width, zero); break;
            case 'x': emit_uint(lng ? va_arg(ap, unsigned long) : (unsigned long)va_arg(ap, unsigned), 16, 0, width, zero); break;
            case 'X': emit_uint(lng ? va_arg(ap, unsigned long) : (unsigned long)va_arg(ap, unsigned), 16, 1, width, zero); break;
            case 'c': uart_send_char((char)va_arg(ap, int)); break;
            case 's': emit_str(va_arg(ap, char *)); break;
            case '%': uart_send_char('%'); break;
            default:  uart_send_char('%'); uart_send_char(*fmt); break;
        }
    }
    va_end(ap);
    return 0;
}
