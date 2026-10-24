/*
 * ipc_limits.h — shared IPC/ABI invariants for the seL4 C glue layer.
 *
 * Single source of truth for the limits shared between the C glue and the
 * Ada/SPARK runtime, so that a compiler/ABI mismatch cannot silently corrupt
 * the message-register window or the shared DMA frame.
 */
#ifndef SCHILD_IPC_LIMITS_H
#define SCHILD_IPC_LIMITS_H

/* seL4 x86_64 ABI: MR[0..3] are delivered in hardware registers
 * (R10/R8/R9/R15); MR[4+] live in the IPC buffer. The Recv stub captures
 * exactly the first four into schild_recv_mr[0..3]. */
#define SCHILD_IPC_MR_COUNT    4u
#define SCHILD_IPC_MR_BYTES    (SCHILD_IPC_MR_COUNT * 8u)

/* Shared DMA frame used for the tx/rx round-trip between the Root Task and
 * NetServer (Stage 8.4, frame @0x520000). */
#define SCHILD_SHARED_FRAME_BYTES 4096u

/* seL4 is not POSIX; these errno-style codes are returned in reply MR[0] to
 * signal a malformed IPC request to the caller. */
#define SCHILD_EBADMSG   74   /* unrecognized operation code / invalid level  */
#define SCHILD_EMSGSIZE  90   /* payload exceeds the shared-frame limit       */

/* Static layout invariants shared with the Ada/SPARK side. */
_Static_assert(sizeof(unsigned long long) == 8,  "message register must be 64-bit");
_Static_assert(_Alignof(unsigned long long) == 8, "message register must be 8-byte aligned");
_Static_assert(SCHILD_IPC_MR_COUNT == 4,          "MR capture window must be 4 registers");
_Static_assert(SCHILD_IPC_MR_BYTES == 32,         "MR capture window must be 32 bytes");
_Static_assert(SCHILD_SHARED_FRAME_BYTES == 4096, "shared DMA frame must be 4096 bytes");

#endif /* SCHILD_IPC_LIMITS_H */
