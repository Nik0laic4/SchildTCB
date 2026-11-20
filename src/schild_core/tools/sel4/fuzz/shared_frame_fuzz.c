/* C4 shared-frame copy fuzz — host test of schild_shared_copy_to/from.
 *
 * #include's the REAL schild_net_runtime.c (no drift from the shipped copy
 * helpers) with the seL4 UART/audit bridge stubbed, mmap's the fixed shared
 * frame (0x52A000, 4 KiB), and fuzzes `len` + bytes under ASan/UBSan with a
 * copy_to -> copy_from roundtrip equality check.
 *
 * Scope: `len` is fuzzed only over [0..4096] (the Ada caller enforces
 * `len <= 4096` before calling — SPARK-checked Pre).  `len > 4096` is out of
 * contract and not fuzzed here.
 *
 * Build: gcc -fsanitize=address,undefined -O1 -g -o shared_frame_fuzz shared_frame_fuzz.c
 * Run:   ./shared_frame_fuzz [iterations]
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>

/* seL4 UART / audit-bridge stubs — the real ones live in the seL4 build. */
void schild_sel4_debug_putchar(unsigned int c) { (void)c; }
void schild_audit_render(void *buffer, int max_len, int *actual_len) {
    (void)buffer; (void)max_len; *actual_len = 0;
}

/* Pull in the REAL shared-frame copy helpers (no drift). */
#include "../src/schild_net_runtime.c"

#define SHARED_FRAME_BYTES 4096

static u64 s = 0x9E3779B97F4A7C15ULL;
static u64 rnd(void) { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s; }

int main(int argc, char **argv) {
    unsigned long iters = 2000000UL;
    if (argc > 1) iters = strtoull(argv[1], 0, 10);

    /* Map the shared frame at its fixed VADDR so the shipped helpers run
     * unmodified (MAP_FIXED_NOREPLACE first, MAP_FIXED fallback). */
    void *frame = mmap((void *)(unsigned long)SHARED_FRAME_VADDR, SHARED_FRAME_BYTES,
                       PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE, -1, 0);
    if (frame == MAP_FAILED)
        frame = mmap((void *)(unsigned long)SHARED_FRAME_VADDR, SHARED_FRAME_BYTES,
                     PROT_READ | PROT_WRITE,
                     MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
    if (frame == MAP_FAILED) { perror("mmap shared frame"); return 2; }

    static unsigned char src[SHARED_FRAME_BYTES];
    static unsigned char dst[SHARED_FRAME_BYTES];

    /* Edge lengths (all in-bounds; the Ada caller enforces len <= 4096). */
    const unsigned len_edges[] = {0, 1, 2, 255, 256, 4095, 4096};

    for (unsigned long i = 0; i < iters; i++) {
        unsigned len = (i < 7) ? len_edges[i]
                               : (unsigned)(rnd() % (SHARED_FRAME_BYTES + 1));
        for (unsigned j = 0; j < SHARED_FRAME_BYTES; j++)
            src[j] = (unsigned char)rnd();

        schild_shared_copy_to(src, len);    /* src -> shared frame */
        schild_shared_copy_from(dst, len);  /* shared frame -> dst */

        if (memcmp(src, dst, len) != 0) {
            fprintf(stderr, "roundtrip mismatch at len=%u\n", len);
            return 1;
        }
    }

    printf("fuzzed %lu shared-frame copy iterations (len 0..4096), no ASan/UBSan violation\n", iters);
    return 0;
}
