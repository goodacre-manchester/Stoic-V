// libc.c — minimal freestanding libc primitives CoreMark needs (-nostdlib).
// SPDX-License-Identifier: Apache-2.0
#include <stddef.h>

void *memcpy(void *d, const void *s, size_t n)
{
    unsigned char *dd = d; const unsigned char *ss = s;
    while (n--) *dd++ = *ss++;
    return d;
}
void *memset(void *d, int c, size_t n)
{
    unsigned char *dd = d;
    while (n--) *dd++ = (unsigned char)c;
    return d;
}
void *memmove(void *d, const void *s, size_t n)
{
    unsigned char *dd = d; const unsigned char *ss = s;
    if (dd < ss) { while (n--) *dd++ = *ss++; }
    else { dd += n; ss += n; while (n--) *--dd = *--ss; }
    return d;
}
int memcmp(const void *a, const void *b, size_t n)
{
    const unsigned char *x = a, *y = b;
    while (n--) { if (*x != *y) return (int)*x - (int)*y; x++; y++; }
    return 0;
}
size_t strlen(const char *s) { const char *p = s; while (*p) p++; return (size_t)(p - s); }
char  *strcpy(char *d, const char *s) { char *r = d; while ((*d++ = *s++)); return r; }
int    strcmp(const char *a, const char *b) { while (*a && *a == *b) { a++; b++; } return (unsigned char)*a - (unsigned char)*b; }
char  *strcat(char *d, const char *s) { char *r = d; while (*d) d++; while ((*d++ = *s++)); return r; }
char  *strncpy(char *d, const char *s, size_t n) { char *r = d; while (n && (*d++ = *s++)) n--; while (n--) *d++ = 0; return r; }
