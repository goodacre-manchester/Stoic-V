// SPDX-License-Identifier: Apache-2.0
// callchain.c — deep call chain with many locals + callee-saved registers. At -O0
// every local is spilled to the stack (store then stack-restore load — the exact
// shape of the P7.1 store→load bug); at -O2/-O3 real prologue/epilogue spill/restore.
volatile int sink;

static int __attribute__((noinline)) leaf(int a, int b, int c, int d) {
    volatile int x = a + b, y = c - d, z = (x * 131) ^ (y + 7);
    sink = z;                     // force a store immediately before the return path
    return x - y + z + (a ^ d);
}
static int __attribute__((noinline)) mid(int n, int seed) {
    int acc = seed;
    for (int i = 0; i < n; i++)
        acc += leaf(i, i + 1, acc & 0xff, i + 3) ^ (acc << 1);
    return acc;
}
static int __attribute__((noinline)) outer(int k) {
    int s = 0;
    for (int j = 1; j <= k; j++) s += mid(j, s + j) - mid(k - j, s);
    return s;
}
int main(void) {
    int s = 0;
    for (int k = 1; k <= 10; k++) s += outer(k);
    return s;
}
