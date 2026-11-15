/* C4 seam fuzz harness — host test of the C shim's buffer handling.
 *
 * Compiles on the host (no seL4): the seL4 `syscall` instruction is not
 * host-fuzzable, so this exercises the memory-safety-relevant paths — the
 * IPC-buffer MR setup (b[1..4]) and the set_mr/set_ec extra-cap writes — with
 * boundary + random 64-bit inputs, under ASan/UBSan.
 *
 * Build: gcc -fsanitize=address,undefined -O1 -g -o seam_fuzz seam_fuzz.c
 * Run:   ./seam_fuzz [iterations]
 */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

typedef unsigned long long u64;
typedef          long long i64;

#define MR_BASE    1
#define EXTRA_BASE 122

static unsigned char g_ipc_buf[4096] __attribute__((aligned(8)));
volatile u64 schild_ipc_buf_addr = 0;

static void set_mr(int n, u64 v) {
    volatile u64 *b = (volatile u64 *)schild_ipc_buf_addr;
    b[MR_BASE + n] = v;
}
static void set_ec(int n, u64 v) {
    volatile u64 *b = (volatile u64 *)schild_ipc_buf_addr;
    b[EXTRA_BASE + n] = v;
}

/* schild_sel4_call4's MR path (the b[1..4] writes) minus the syscall. */
i64 schild_sel4_call4_mem(u64 mr0, u64 mr1, u64 mr2, u64 mr3) {
    volatile u64 *b = (volatile u64 *)schild_ipc_buf_addr;
    b[1] = mr0; b[2] = mr1; b[3] = mr2; b[4] = mr3;
    return 0;
}

/* xorshift64* deterministic PRNG. */
static u64 s = 0x9E3779B97F4A7C15ULL;
static u64 rnd(void) { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s; }

int main(int argc, char **argv) {
    unsigned long iters = 10000000UL;
    if (argc > 1) iters = strtoull(argv[1], 0, 10);
    schild_ipc_buf_addr = (u64)g_ipc_buf;

    const u64 edges[] = {0, 1, 0x7FFFFFFFFFFFFFFFULL, 0x8000000000000000ULL,
                         0xFFFFFFFFFFFFFFFFULL, 0xFFFFFFFFFFFFFFFEULL};

    for (unsigned long i = 0; i < iters; i++) {
        u64 mr0 = (i < 6) ? edges[i] : rnd();
        u64 mr1 = rnd(); u64 mr2 = rnd(); u64 mr3 = rnd();
        (void)schild_sel4_call4_mem(mr0, mr1, mr2, mr3);
        set_mr(0, mr0); set_mr(1, mr1); set_mr(2, mr2); set_mr(3, mr3);
        set_mr(4, rnd()); set_mr(5, rnd());
        set_ec(0, rnd()); set_ec(1, rnd()); set_ec(2, rnd());
    }

    printf("fuzzed %lu iterations, no ASan/UBSan violation\n", iters);
    return 0;
}
