// SPDX-License-Identifier: Apache-2.0
// memops.c — array-of-structs copy + sub-word field access + a store immediately
// before reads: back-to-back loads/stores and byte/halfword enables, the canonical
// "store then load a different address" the free-running slave stresses.
struct P { unsigned char a; signed short b; int c; unsigned char d; };
static struct P src[24], dst[24];
volatile int marker;

int main(void) {
    for (int i = 0; i < 24; i++) {
        src[i].a = (unsigned char)(i * 3 + 1);
        src[i].b = (signed short)(i * 137 - 200);
        src[i].c = i * 131 + 5;
        src[i].d = (unsigned char)(255 - i);
    }
    for (int i = 0; i < 24; i++) {
        marker = i;            // STORE immediately before the struct-copy loads
        dst[i] = src[i];       // struct copy: back-to-back ld/st, mixed widths
    }
    int s = 0;
    for (int i = 0; i < 24; i++)
        s += dst[i].a + dst[i].b + dst[i].c + dst[i].d - dst[23 - i].b;
    return s;
}
