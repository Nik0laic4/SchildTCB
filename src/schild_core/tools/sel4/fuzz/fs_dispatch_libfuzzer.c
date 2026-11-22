/* C4 fs-dispatch libFuzzer harness — coverage-guided version of
 * fs_dispatch_fuzz.c. Same no-drift trick (#include the real fs_daemon.c).
 *
 * Build: clang -fsanitize=fuzzer,address,undefined -O1 -g -I../src -o fs_dispatch_libfuzzer fs_dispatch_libfuzzer.c
 */
#include <stdint.h>
#include <stddef.h>
#include <string.h>

typedef unsigned long long u64;
typedef          long long i64;
typedef unsigned int       u32;

volatile u64 schild_recv_mr[4];
volatile u64 schild_reply_mr[4];
volatile u64 fs_daemon_alive_flag = 0;

void fs_daemon_entry(void) {}
char fs_daemon_stack_top[4096];

i64 schild_sel4_recv(u64 src, u64 reply) { (void)src; (void)reply; return 0; }
i64 schild_sel4_replyrecv(u64 src, u64 info, u64 reply) { (void)src; (void)info; (void)reply; return 0; }
i64 schild_sel4_reply_only(u64 reply, u64 info) { (void)reply; (void)info; return 0; }
i64 schild_sel4_signal(u64 dest) { (void)dest; return 0; }
unsigned int schild_mls_authorize_ipc_levels(unsigned int sender_level, unsigned int receiver_level)
    { (void)sender_level; (void)receiver_level; return 1; }

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

#include "../src/fs_daemon.c"

static u64 load64(const uint8_t *d, size_t n, size_t i) {
    u64 v = 0; size_t base = i * 8;
    for (size_t j = 0; j < 8; j++)
        v = (v << 8) | (base + j < n ? d[base + j] : (uint8_t)(i + j));
    return v;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    u64 op = load64(data, size, 0);
    u64 a  = load64(data, size, 1);
    u64 b  = load64(data, size, 2);
    u64 c  = load64(data, size, 3);
    u64 r0, r1, r2, r3; int f;
    fs_dispatch(op, a, b, c, &r0, &r1, &r2, &r3, &f);
    return 0;
}
