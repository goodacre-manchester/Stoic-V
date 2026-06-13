// SPDX-License-Identifier: Apache-2.0
// sortsum.c — insertion sort (in-place swaps = store/load pairs) + prefix sums +
// a recursive checksum. Mixed compute + memory traffic with stack recursion.
static int buf[48];

static int __attribute__((noinline)) chk(int *a, int n) {   // recursive: deep stack
    if (n == 0) return 0;
    int rest = chk(a, n - 1);
    return (rest * 31 + a[n - 1]) & 0x7fffffff;
}
int main(void) {
    unsigned x = 0x1234567u;
    for (int i = 0; i < 48; i++) { x = x * 1103515245u + 12345u; buf[i] = (int)((x >> 8) & 0x3ff) - 512; }
    // insertion sort (in-place: read-modify-write back-to-back)
    for (int i = 1; i < 48; i++) {
        int key = buf[i], j = i - 1;
        while (j >= 0 && buf[j] > key) { buf[j + 1] = buf[j]; j--; }
        buf[j + 1] = key;
    }
    // prefix sums in place
    for (int i = 1; i < 48; i++) buf[i] += buf[i - 1];
    return chk(buf, 48) + buf[47];
}
