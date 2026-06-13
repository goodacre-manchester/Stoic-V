// SPDX-License-Identifier: Apache-2.0
// ptrchase.c — linked-list build + traverse: a loaded pointer is the next load's
// base (load→load AGEN), and a store-into-node sits right before the next chase load.
struct N { struct N *next; int val; int tag; };
static struct N pool[40];
volatile int touch;

int main(void) {
    // build a non-trivial chain order (stride 7 mod 40) so next pointers jump around
    int idx = 0;
    for (int i = 0; i < 40; i++) {
        pool[idx].val = idx * idx - 7 * idx + 3;
        pool[idx].tag = i;
        int nxt = (idx + 7) % 40;
        pool[idx].next = (i + 1 < 40) ? &pool[nxt] : (struct N *)0;
        idx = nxt;
    }
    int s = 0;
    for (struct N *p = &pool[0]; p; p = p->next) {
        touch = p->tag;            // STORE before the chase load
        s += p->val ^ (p->tag << 2);
        p->val = s;                // write-back into the node (store) before p=p->next
    }
    return s;
}
