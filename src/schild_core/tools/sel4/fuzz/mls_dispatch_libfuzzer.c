/* C4 mls-dispatch libFuzzer harness — coverage-guided version of
 * mls_dispatch_fuzz.c (drift caveat: dispatch is a copy, keep in sync).
 *
 * Build: clang -fsanitize=fuzzer,address,undefined -O1 -g -o mls_dispatch_libfuzzer mls_dispatch_libfuzzer.c
 */
#include <stdint.h>
#include <stddef.h>

typedef unsigned long long u64;
typedef unsigned int       u32;

#define SCHILD_EBADMSG 74

static u32 schild_mls_authorize_op(u32 op, u32 sender_level, u32 target_level)
    { (void)op; (void)sender_level; (void)target_level; return 1; }

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

static u64 load64(const uint8_t *d, size_t n, size_t i) {
    u64 v = 0; size_t base = i * 8;
    for (size_t j = 0; j < 8; j++)
        v = (v << 8) | (base + j < n ? d[base + j] : (uint8_t)(i + j));
    return v;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    u64 op = load64(data, size, 0);
    u64 target = load64(data, size, 1);
    u64 sender = load64(data, size, 2);
    u64 r0; int f;
    mls_dispatch(op, target, sender, &r0, &f);
    return 0;
}
