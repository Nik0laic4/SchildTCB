/* C4 shared-frame copy libFuzzer harness — coverage-guided version of
 * shared_frame_fuzz.c. Same no-drift trick (#include the real
 * schild_net_runtime.c), same roundtrip equality oracle, but driven by
 * libFuzzer's coverage-guided mutator instead of xorshift64.
 *
 * Build: clang -fsanitize=fuzzer,address,undefined -O1 -g -o shared_frame_libfuzzer shared_frame_libfuzzer.c
 * Run:   ./shared_frame_libfuzzer -max_total_time=60
 */
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdlib.h>
#include <sys/mman.h>

void schild_sel4_debug_putchar(unsigned int c) { (void)c; }
void schild_audit_render(void *buffer, int max_len, int *actual_len) {
    (void)buffer; (void)max_len; *actual_len = 0;
}

#include "../src/schild_net_runtime.c"

#define SHARED_FRAME_BYTES 4096

static int mapped = 0;
static void ensure_frame(void) {
    if (mapped) return;
    void *frame = mmap((void *)(unsigned long)SHARED_FRAME_VADDR, SHARED_FRAME_BYTES,
                       PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE, -1, 0);
    if (frame == MAP_FAILED)
        frame = mmap((void *)(unsigned long)SHARED_FRAME_VADDR, SHARED_FRAME_BYTES,
                     PROT_READ | PROT_WRITE,
                     MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
    if (frame == MAP_FAILED) abort();
    mapped = 1;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    ensure_frame();

    static unsigned char src[SHARED_FRAME_BYTES];
    static unsigned char dst[SHARED_FRAME_BYTES];

    /* len derives from the input: 0..4096 (the Ada caller enforces <= 4096). */
    unsigned len = (unsigned)(size % (SHARED_FRAME_BYTES + 1));
    for (unsigned j = 0; j < SHARED_FRAME_BYTES; j++)
        src[j] = (j < size) ? data[j] : (unsigned char)(j * 31u + 7u);

    schild_shared_copy_to(src, len);
    schild_shared_copy_from(dst, len);

    if (memcmp(src, dst, len) != 0) abort();
    return 0;
}
