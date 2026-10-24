/* Schild TCB Stage 7.7 — MLS Policy Server Thread
 *
 * Receives IPC on its configured endpoint, performs Bell-LaPadula
 * access checks, and replies with the result.
 *
 * IPC buffer: dedicated 4KB frame at 0x500000 (set by Root Task).
 * MR layout:  MR[0]=op  MR[1]=target_level
 * Reply:       MR[0]=result (0=denied, 1=allowed)
 */
#include "ipc_limits.h"

typedef unsigned long long u64;
typedef          long long i64;
extern i64 schild_sel4_recv(u64 src, u64 reply);
extern i64 schild_sel4_replyrecv(u64 src, u64 info, u64 reply);
extern i64 schild_sel4_reply_only(u64 reply, u64 info);
extern volatile u64 mls_reply_cptr;

/* IPC buffer address — set by Root Task via schild_set_mls_ipc_buf.
 * NOTE: on x86_64 seL4, MR[0..3] are delivered in hardware registers
 * (R10/R8/R9/R15), NOT in the IPC buffer (which only holds MR[4+]).
 * The Recv stub captures them into schild_recv_mr[0..3]. */
extern volatile u64 mls_ipc_buf_addr;
extern volatile u64 schild_recv_mr[4];
extern volatile u64 schild_reply_mr[4];

/* Verified Ada Bell-LaPadula gate (schild_mls_policy). 1 = allowed, 0 = denied. */
extern unsigned int schild_mls_authorize_op(unsigned int op,
                                            unsigned int sender_level,
                                            unsigned int target_level);

/* Shared-layout invariants: the C MR window must match the Ada/SPARK view. */
_Static_assert(sizeof(schild_recv_mr) == SCHILD_IPC_MR_BYTES,  "recv MR window must be 32 bytes");
_Static_assert(sizeof(schild_reply_mr) == SCHILD_IPC_MR_BYTES, "reply MR window must be 32 bytes");

void mls_server_main(void) {
    u64 endpoint = 0;
    extern volatile u64 mls_endpoint_cptr;
    endpoint = mls_endpoint_cptr;
    u64 reply = mls_reply_cptr;

    /* B1 fix: if no endpoint/reply configured, signal error and halt */
    if (endpoint == 0 || reply == 0) {
        extern char mls_alive_flag;
        mls_alive_flag = 0xFF;  /* error marker */
        for (;;) __asm__ volatile("pause");
    }

    u64 badge = schild_sel4_recv(endpoint, reply);

    for (;;) {
        u64 sender_level = badge & 0xFF;

        /* H1 fix: read MR[0]/MR[1] from the hardware message registers
         * captured by the Recv stub (seL4 x86_64 ABI). */
        u64 op = schild_recv_mr[0];           /* MR[0] — operation code */
        u64 target_level = schild_recv_mr[1]; /* MR[1] — target clearance */

        u64 result;
        int fault_after_reply = 0;
        if (op == 99) {
            /* Crash-containment test: reply first, then fault on unmapped
             * 0xFFFFF000 so seL4 delivers a #PF to the MLS fault endpoint
             * (slot 199). */
            result = 0;
            fault_after_reply = 1;
        } else if (op > 2) {
            /* Unknown MLS operation — reject before any level comparison. */
            result = SCHILD_EBADMSG;
        } else if (target_level > 4) {
            /* Clearance outside the 5-level MLS range (0..4). */
            result = SCHILD_EBADMSG;
        } else {
            /* Delegate the Bell-LaPadula decision to the verified Ada policy
             * (schild_mls_policy) instead of an unverified inline C check. */
            result = (u64)schild_mls_authorize_op((unsigned int)op,
                                                  (unsigned int)sender_level,
                                                  (unsigned int)target_level);
        }

        /* Stage reply MR[0..3] — the Reply stub loads them into R10/R8/R9/R15 */
        schild_reply_mr[0] = result;
        schild_reply_mr[1] = 0;
        schild_reply_mr[2] = 0;
        schild_reply_mr[3] = 0;

        if (fault_after_reply) {
            schild_sel4_reply_only(reply, 1ULL);
            *(volatile unsigned long long *)0x00000000FFFFF000ULL =
                0xDEADBEEFDEADBEEFULL;
            /* unreachable */
        }

        badge = schild_sel4_replyrecv(endpoint, 1ULL, reply);  /* reply + recv */
    }
}
volatile u64 mls_endpoint_cptr = 0;
volatile u64 mls_reply_cptr = 0;
