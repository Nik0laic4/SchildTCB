/* C4 daemon-dispatch fuzz — host test of fs_daemon.c's op switch.
 *
 * Replicates the fs_daemon.c dispatch (op switch + u32 arg casts + reply MR
 * writes) with the seL4 syscalls and the Ada FS server stubbed, and fuzzes
 * op/mr[0..3] under ASan/UBSan.  This gives empirical "the dispatch doesn't
 * crash on N untrusted op/arg inputs", not a proof.  (Drift caveat: this is a
 * copy of the switch; a follow-up extracts the real dispatch into a shared
 * function so the harness includes it directly.)
 *
 * Build: gcc -fsanitize=address,undefined -O1 -g -o fs_dispatch_fuzz fs_dispatch_fuzz.c
 * Run:   ./fs_dispatch_fuzz [iterations]
 */
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

typedef unsigned long long u64;
typedef unsigned int       u32;

#define SCHILD_EBADMSG 13

/* Stubbed Ada FS exports (Schild_Fs_Server, Convention C). */
static u32 schild_fs_init(void) { return 0; }
static u32 schild_fs_open(u32 n, u32* h, u32* s) { (void)n; if (h) *h = 0; if (s) *s = 0; return 0; }
static u32 schild_fs_read(u32 h, u32 o, u32 l, u32* act) { (void)h; (void)o; (void)l; if (act) *act = 0; return 0; }
static u32 schild_fs_write(u32 h, u32 o, u32 l, u32* no) { (void)h; (void)o; (void)l; if (no) *no = 0; return 0; }
static u32 schild_fs_create(u32 n, u32 s, u32* h) { (void)n; (void)s; if (h) *h = 0; return 0; }
static u32 schild_fs_append(u32 n, u32 l, u32* ns) { (void)n; (void)l; if (ns) *ns = 0; return 0; }
static u32 schild_fs_get_entry(u32 i) { (void)i; return 0; }
static u32 schild_fs_is_mounted(void) { return 0; }
static u32 schild_fs_is_read_only(void) { return 0; }
static u32 schild_fs_delete(u32 n) { (void)n; return 0; }

static volatile u64 schild_recv_mr[4];
static volatile u64 schild_reply_mr[4];

/* The fs_daemon.c dispatch (op switch + arg casts + reply MR writes). */
static void fs_dispatch(u64 op, u64 a, u64 b, u64 c) {
    u64 result = SCHILD_EBADMSG, result1 = 0, result2 = 0, result3 = 0;
    switch (op) {
    case 0: result = (u64)schild_fs_init(); break;
    case 1: { u32 h = 0, s = 0;
              result = (u64)schild_fs_open((u32)a, &h, &s); result1 = h; result2 = s; break; }
    case 2: { u32 act = 0;
              result = (u64)schild_fs_read((u32)a, (u32)b, (u32)c, &act); result1 = act; break; }
    case 3: { u32 no = 0;
              result = (u64)schild_fs_write((u32)a, (u32)b, (u32)c, &no); result1 = no; break; }
    case 4: { u32 h = 0;
              result = (u64)schild_fs_create((u32)a, (u32)b, &h); result1 = h; break; }
    case 5: { u32 ns = 0;
              result = (u64)schild_fs_append((u32)a, (u32)b, &ns); result1 = ns; break; }
    case 6: result = (u64)schild_fs_get_entry((u32)a); break;
    case 7: result = (u64)schild_fs_is_mounted(); break;
    case 8: result = (u64)schild_fs_is_read_only(); break;
    case 9: result = (u64)schild_fs_delete((u32)a); break;
    case 99: result = 0; break;
    default: result = SCHILD_EBADMSG; break;
    }
    schild_reply_mr[0] = result;
    schild_reply_mr[1] = result1;
    schild_reply_mr[2] = result2;
    schild_reply_mr[3] = result3;
}

static u64 s = 0x9E3779B97F4A7C15ULL;
static u64 rnd(void) { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s; }

int main(int argc, char **argv) {
    unsigned long iters = 10000000UL;
    if (argc > 1) iters = strtoull(argv[1], 0, 10);
    const u64 edges[] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 99,
                         0x7FFFFFFFFFFFFFFFULL, 0x8000000000000000ULL, 0xFFFFFFFFFFFFFFFFULL};
    for (unsigned long i = 0; i < iters; i++) {
        u64 op = (i < 14) ? edges[i] : rnd();
        u64 a = rnd(), b = rnd(), c = rnd();
        schild_recv_mr[0] = op; schild_recv_mr[1] = a;
        schild_recv_mr[2] = b; schild_recv_mr[3] = c;
        fs_dispatch(op, a, b, c);
    }
    printf("fuzzed %lu dispatch iterations, no ASan/UBSan violation\n", iters);
    return 0;
}
