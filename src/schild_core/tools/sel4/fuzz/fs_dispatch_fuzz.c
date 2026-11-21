/* C4 daemon-dispatch fuzz — host test of fs_daemon.c's REAL fs_dispatch().
 *
 * #include's the actual fs_daemon.c (no drift from the shipped dispatch) with
 * the seL4 syscalls and the Ada FS server stubbed, and fuzzes op/mr[0..3] under
 * ASan/UBSan.  This gives empirical "the shipped dispatch doesn't crash on N
 * untrusted op/arg inputs", not a proof.
 *
 * Build: gcc -fsanitize=address,undefined -O1 -g -I../src -o fs_dispatch_fuzz fs_dispatch_fuzz.c
 * Run:   ./fs_dispatch_fuzz [iterations]
 */
#include <stdio.h>
#include <stdlib.h>

typedef unsigned long long u64;
typedef          long long i64;
typedef unsigned int       u32;

/* Globals that fs_daemon.c declares extern (defined here; the C daemon's own
 * fs_endpoint_cptr/fs_reply_cptr definitions come with the #include below). */
volatile u64 schild_recv_mr[4];
volatile u64 schild_reply_mr[4];
volatile u64 fs_daemon_alive_flag = 0;

/* Link-only symbols referenced by fs_daemon.c's accessor helpers. */
void fs_daemon_entry(void) {}
char fs_daemon_stack_top[4096];

/* seL4 syscall stubs (the real ones live in schild_sel4_syscalls.S). */
i64 schild_sel4_recv(u64 src, u64 reply) { (void)src; (void)reply; return 0; }
i64 schild_sel4_replyrecv(u64 src, u64 info, u64 reply) { (void)src; (void)info; (void)reply; return 0; }
i64 schild_sel4_reply_only(u64 reply, u64 info) { (void)reply; (void)info; return 0; }
i64 schild_sel4_signal(u64 dest) { (void)dest; return 0; }
unsigned int schild_mls_authorize_ipc_levels(unsigned int sender_level, unsigned int receiver_level)
    { (void)sender_level; (void)receiver_level; return 1; }

/* Ada FS server stubs (Schild_Fs_Server, Convention C). */
u32 schild_fs_init(void) { return 0; }
u32 schild_fs_open(u32 n, u32 m, u32 *h, u32 *s) { (void)n; (void)m; if (h) *h = 0; if (s) *s = 0; return 0; }
void schild_set_fs_subject(unsigned int role, unsigned int level) { (void)role; (void)level; }
u32 schild_fs_read(u32 h, u32 o, u32 l, u32 *a) { (void)h; (void)o; (void)l; if (a) *a = 0; return 0; }
u32 schild_fs_write(u32 h, u32 o, u32 l, u32 *n) { (void)h; (void)o; (void)l; if (n) *n = 0; return 0; }
u32 schild_fs_create(u32 n, u32 s, u32 lv, u32 *h) { (void)n; (void)s; (void)lv; if (h) *h = 0; return 0; }
u32 schild_fs_append(u32 n, u32 l, u32 *ns) { (void)n; (void)l; if (ns) *ns = 0; return 0; }
u32 schild_fs_get_entry(u32 i) { (void)i; return 0; }
u32 schild_fs_is_mounted(void) { return 0; }
u32 schild_fs_is_read_only(void) { return 0; }
u32 schild_fs_delete(u32 n) { (void)n; return 0; }

/* Pull in the real fs_daemon.c dispatch (fs_dispatch + fs_daemon_main). */
#include "../src/fs_daemon.c"

static u64 s = 0x9E3779B97F4A7C15ULL;
static u64 rnd(void) { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s; }

int main(int argc, char **argv) {
    unsigned long iters = 2000000UL;
    if (argc > 1) iters = strtoull(argv[1], 0, 10);
    const u64 edges[] = {0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 99,
                         0x7FFFFFFFFFFFFFFFULL, 0x8000000000000000ULL, 0xFFFFFFFFFFFFFFFFULL};
    for (unsigned long i = 0; i < iters; i++) {
        u64 op = (i < 14) ? edges[i] : rnd();
        u64 a = rnd(), b = rnd(), c = rnd();
        u64 r0, r1, r2, r3; int f;
        fs_dispatch(op, a, b, c, &r0, &r1, &r2, &r3, &f);
    }
    printf("fuzzed %lu dispatch iterations, no ASan/UBSan violation\n", iters);
    return 0;
}
