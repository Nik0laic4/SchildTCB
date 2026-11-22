/* C4 seam libFuzzer harness — coverage-guided version of seam_fuzz.c.
 * Exercises the same memory-safety-relevant paths (MR setup b[1..4] +
 * set_mr/set_ec extra-cap writes) under libFuzzer's mutator.
 *
 * Build: clang -fsanitize=fuzzer,address,undefined -O1 -g -o seam_libfuzzer seam_libfuzzer.c
 */
#include <stdint.h>
#include <stddef.h>
#include <string.h>

typedef unsigned long long u64;
typedef          long long i64;

#define MR_BASE    1
#define EXTRA_BASE 122

static unsigned char g_ipc_buf[4096] __attribute__((aligned(8)));
volatile u64 schild_ipc_buf_addr = 0;

static void set_mr(int n, u64 v) { volatile u64 *b = (volatile u64 *)schild_ipc_buf_addr; b[MR_BASE + n] = v; }
static void set_ec(int n, u64 v) { volatile u64 *b = (volatile u64 *)schild_ipc_buf_addr; b[EXTRA_BASE + n] = v; }

i64 schild_sel4_call4_mem(u64 mr0, u64 mr1, u64 mr2, u64 mr3) {
    volatile u64 *b = (volatile u64 *)schild_ipc_buf_addr;
    b[1] = mr0; b[2] = mr1; b[3] = mr2; b[4] = mr3;
    return 0;
}

static u64 load64(const uint8_t *d, size_t n, size_t i) {
    u64 v = 0;
    size_t base = i * 8;
    for (size_t j = 0; j < 8; j++)
        v = (v << 8) | (base + j < n ? d[base + j] : (uint8_t)(i + j));
    return v;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    if (schild_ipc_buf_addr == 0) schild_ipc_buf_addr = (u64)g_ipc_buf;

    u64 mr0 = load64(data, size, 0), mr1 = load64(data, size, 1);
    u64 mr2 = load64(data, size, 2), mr3 = load64(data, size, 3);
    (void)schild_sel4_call4_mem(mr0, mr1, mr2, mr3);
    set_mr(0, mr0); set_mr(1, mr1); set_mr(2, mr2); set_mr(3, mr3);
    set_mr(4, load64(data, size, 4)); set_mr(5, load64(data, size, 5));
    set_ec(0, load64(data, size, 6)); set_ec(1, load64(data, size, 7));
    set_ec(2, mr0 ^ mr1 ^ mr2 ^ mr3);
    return 0;
}
