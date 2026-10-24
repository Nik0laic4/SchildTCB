/* Schild TCB Stage 8.1D — NetServer thread (Ring 3).
 *
 * Receives IPC on the net_ep endpoint, executes the requested network
 * operation (0=init, 1=poll_rx) via the Ada driver/stack, and replies.
 *
 * MR layout:  MR[0] = op   (0=init, 1=poll_rx, 2=tx_frame, 3=rx_frame)
 * Reply:      MR[0] = status (0=ok/no-packet, 1=packet, 2=unknown-op, 3=err)
 *             MR[1] = tx echo byte (op=2) / rx frame length (op=3)
 */
#include "ipc_limits.h"

typedef unsigned long long u64;
typedef          long long i64;
extern i64 schild_sel4_recv(u64 src, u64 reply);
extern i64 schild_sel4_replyrecv(u64 src, u64 info, u64 reply);
extern i64 schild_sel4_reply_only(u64 reply, u64 info);
extern volatile u64 net_reply_cptr;
extern volatile u64 schild_recv_mr[4];
extern volatile u64 schild_reply_mr[4];
extern volatile u64 schild_net_endpoint_cptr;

/* Shared-layout invariants: the C MR window must match the Ada/SPARK view. */
_Static_assert(sizeof(schild_recv_mr) == SCHILD_IPC_MR_BYTES,  "recv MR window must be 32 bytes");
_Static_assert(sizeof(schild_reply_mr) == SCHILD_IPC_MR_BYTES, "reply MR window must be 32 bytes");
extern unsigned int schild_net_init(void);
extern unsigned int schild_net_poll(void);
extern unsigned int schild_net_tx_shared(unsigned int len);
extern unsigned int schild_net_rx_shared(void);

void netserver_main(void) {
    u64 ep = schild_net_endpoint_cptr;
    u64 reply = net_reply_cptr;

    if (ep == 0 || reply == 0) {
        for (;;) __asm__ volatile("pause");
    }

    schild_sel4_recv(ep, reply);

    for (;;) {
        u64 op = schild_recv_mr[0];
        u64 result = SCHILD_EBADMSG;  /* reject unrecognized op by default */
        u64 result2 = 0;  /* secondary result (echo byte / rx length) */
        int fault_after_reply = 0;   /* set by the crash-containment op */

        if (op == 0) {
            result = schild_net_init();
        } else if (op == 1) {
            result = schild_net_poll();
        } else if (op == 2) {
            /* tx_frame: frame already placed in the shared frame @0x520000,
             * length in MR[1]. Reject a length that would overrun the 4 KB
             * shared frame before it reaches the Ada driver. */
            u64 len = schild_recv_mr[1];
            if (len > SCHILD_SHARED_FRAME_BYTES) {
                result  = SCHILD_EMSGSIZE;
                result2 = 0;
            } else {
                result2 = schild_net_tx_shared((unsigned int)len);
                result  = (result2 == 0xFFFFFFFFu) ? 3 : 0;
            }
        } else if (op == 3) {
            /* rx_frame: copy the next RX frame into the shared frame; the
             * frame length is returned in MR[1] (0 = no packet). */
            result2 = schild_net_rx_shared();
            result = (result2 > 0) ? 1 : 0;
        } else if (op == 4) {
            /* bench noop: reply immediately (no NIC access) — IPC latency
             * probe for the seL4 Fastpath benchmark. */
            result = 0;
        } else if (op == 99) {
            /* Crash-containment test: reply first (so the root task's
             * Call_IPC returns), THEN fault on unmapped 0xFFFFF000. seL4
             * delivers the #PF to the NetServer's fault endpoint. */
            result = 0;
            fault_after_reply = 1;
        }

        schild_reply_mr[0] = result;
        schild_reply_mr[1] = result2;
        schild_reply_mr[2] = 0;
        schild_reply_mr[3] = 0;

        if (fault_after_reply) {
            /* Reply first (so the root task's Call returns), then fault on an
             * unmapped page.  seL4 delivers the #PF to the NetServer's fault
             * endpoint (badge 0xE2). */
            schild_sel4_reply_only(reply, 2ULL);
            *(volatile unsigned long long *)0x00000000FFFFF000ULL =
                0xDEADBEEFDEADBEEFULL;
            /* unreachable */
        }

        schild_sel4_replyrecv(ep, 2ULL, reply);  /* 2 MRs; reply + next recv */
    }
}

volatile u64 schild_net_endpoint_cptr = 0;
volatile u64 net_reply_cptr = 0;
