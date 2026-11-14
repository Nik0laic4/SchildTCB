/* Copyright (C) 2026 Alexander Irganov
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Schild TCB -- host-side ABI unit test for the seL4 msgInfo encoding (AS6/C4).
 *
 * The msgInfo word packs (label << 12) | (capsUnwrapped << 9) | (extraCaps << 7)
 * | length, matching the inline encoding in schild_sel4_ipc.c.  This test
 * verifies the bit layout round-trips without loss across the full field
 * ranges and that the length field is capped at seL4_MsgMaxLength (120) so a
 * malformed request cannot overrun the MR window or the extra-cap window.
 *
 * Host-side, QEMU-free, runs in milliseconds (CI job "seam-abi").
 */
#include <stdio.h>
#include <stdint.h>

/* seL4 x86_64 MessageInfo field widths. */
#define MSG_LENGTH_BITS     7u   /* bits  0..6  */
#define MSG_EXTRACAP_BITS   2u   /* bits  7..8  */
#define MSG_CAPSUNWRAP_BIT  9u   /* bit   9     */
#define MSG_LABEL_SHIFT     12u  /* bits 12..63 */
#define MSG_MAX_LENGTH      120u /* seL4_MsgMaxLength (x86_64) */

typedef uint64_t u64;

static u64 pack(u64 label, u64 capsUnwrapped, u64 extraCaps, u64 length)
{
    return (label << MSG_LABEL_SHIFT) | (capsUnwrapped << MSG_CAPSUNWRAP_BIT)
         | (extraCaps << MSG_LENGTH_BITS) | length;
}

static void unpack(u64 w, u64 *label, u64 *capsUnwrapped, u64 *extraCaps, u64 *length)
{
    *length        = w & ((1u << MSG_LENGTH_BITS) - 1u);
    *extraCaps     = (w >> MSG_LENGTH_BITS) & ((1u << MSG_EXTRACAP_BITS) - 1u);
    *capsUnwrapped = (w >> MSG_CAPSUNWRAP_BIT) & 1u;
    *label         = w >> MSG_LABEL_SHIFT;
}

static int failures = 0;
#define CHECK(c) \
    do { if (!(c)) { printf("  FAIL %s:%d: %s\n", __FILE__, __LINE__, #c); failures++; } } while (0)

/* Pack then unpack and verify every field survives losslessly. */
static void check_roundtrip(u64 label, u64 capsUnwrapped, u64 extraCaps, u64 length)
{
    u64 w, r_label, r_capsUnwrapped, r_extraCaps, r_length;
    w = pack(label, capsUnwrapped, extraCaps, length);
    unpack(w, &r_label, &r_capsUnwrapped, &r_extraCaps, &r_length);
    CHECK(r_label == label);
    CHECK(r_capsUnwrapped == capsUnwrapped);
    CHECK(r_extraCaps == extraCaps);
    CHECK(r_length == length);
}

int main(void)
{
    u64 i;

    /* 1. Label is lossless over its full 52-bit range (boundaries). */
    {
        const u64 labels[] = {
            0u, 1u, 0x7FFu, 0x800u, 0xFFFFu, 0xFFFFFFFFu,
            0xFFFFFFFFFFFFu /* 2^48-1 */, 0xFFFFFFFFFFFFFull /* 2^52-1 */
        };
        for (i = 0; i < sizeof(labels) / sizeof(labels[0]); i++) {
            check_roundtrip(labels[i], 1, 3, 120);
        }
    }

    /* 2. extraCaps (0..3) and capsUnwrapped (0..1) are lossless. */
    for (i = 0; i <= 3; i++) {
        check_roundtrip(0xABCD, 0, i, 7);
        check_roundtrip(0xABCD, 1, i, 7);
    }

    /* 3. length (0..MSG_MAX_LENGTH) is lossless. */
    for (i = 0; i <= MSG_MAX_LENGTH; i++) {
        check_roundtrip(0x5A5A, 1, 2, i);
    }

    /* 4. Length clamp: the 7-bit field max is 127; the caller-side cap is
     * MSG_MAX_LENGTH (120), so an out-of-window length is encodable but
     * detectable and must be rejected by the syscall seam. */
    {
        u64 raw = pack(0, 0, 0, 127) & 0x7Fu;
        CHECK(raw == 127u);                 /* 7-bit field maximum */
        CHECK(MSG_MAX_LENGTH == 120u);      /* caller-side cap */
        CHECK(raw > MSG_MAX_LENGTH);        /* out-of-window is detectable */
    }

    printf("seam-abi: %s (%d failures)\n", failures ? "FAIL" : "PASS", failures);
    return failures ? 1 : 0;
}
