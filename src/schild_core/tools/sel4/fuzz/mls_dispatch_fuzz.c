/* C4 daemon-dispatch fuzz — host test of mls_server.c's op dispatch.
 *
 * Replicates the mls_server.c dispatch (op/target_level checks + u32 casts into
 * the Ada gate) with the Ada stubbed, and fuzzes op/target_level/sender_level
 * under ASan/UBSan.  Drift caveat: this is a copy of the dispatch (the
 * "extract-into-shared-function" refactor perturbed the H87 size-sensitive ELF
 * layout and broke run_tests), so keep it in sync manually.
 *
 * Build: gcc -fsanitize=address,undefined -O1 -g -o mls_dispatch_fuzz mls_dispatch_fuzz.c
 * Run:   ./mls_dispatch_fuzz [iterations]
 */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

typedef unsigned long long u64;
typedef unsigned int       u32;

#define SCHILD_EBADMSG 74

static u32 schild_mls_authorize_op(u32 op, u32 sender_level, u32 target_level)
    { (void)op; (void)sender_level; (void)target_level; return 1; }

/* The mls_server.c dispatch (copy — see the drift caveat above). */
static void mls_dispatch(u64 op, u64 target_level, u64 sender_level,
                         u64 *r0, int *fault) {
    u64 result = SCHILD_EBADMSG;
    int fault_after_reply = 0;
    if (op == 99) {
        result = 0;
        fault_after_reply = 1;
    } else if (op > 2) {
        result = SCHILD_EBADMSG;
    } else if (target_level > 4) {
        result = SCHILD_EBADMSG;
    } else {
        result = (u64)schild_mls_authorize_op((u32)op, (u32)sender_level, (u32)target_level);
    }
    *r0 = result;
    *fault = fault_after_reply;
}

static u64 s = 0x9E3779B97F4A7C15ULL;
static u64 rnd(void) { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s; }

int main(int argc, char **argv) {
    unsigned long iters = 2000000UL;
    if (argc > 1) iters = strtoull(argv[1], 0, 10);
    const u64 edges[] = {0, 1, 2, 3, 4, 5, 99, 0xFFFFFFFFFFFFFFFFULL};
    for (unsigned long i = 0; i < iters; i++) {
        u64 op = (i < 8) ? edges[i] : rnd();
        u64 target = rnd();
        u64 sender = rnd();
        u64 r0; int f;
        mls_dispatch(op, target, sender, &r0, &f);
    }
    printf("fuzzed %lu MLS-dispatch iterations, no ASan/UBSan violation\n", iters);
    return 0;
}
