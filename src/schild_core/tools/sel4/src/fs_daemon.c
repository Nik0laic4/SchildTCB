/* Schild TCB — FS Daemon thread (audit H65/H86 Stage 1).
 *
 * Stage 1 scope: thread live + Recv loop. All ops return EBADMSG.
 * Stage 2 will add dispatch to Ada exports (schild_fs_*).
 * Stage 3 will add NVMe ownership migration from NetServer (H86).
 *
 * IPC buffer: dedicated 4KB frame at 0x530000 (set by Root Task).
 * MR layout (Stage 2+): MR[0]=op, MR[1..3]=args
 *   op 0 = Init, 1 = Open, 2 = Read, 3 = Write, 4 = Create, 5 = Append,
 *   6 = Get_Entry, 7 = Is_Mounted, 8 = Is_Read_Only, 99 = fault injection (test)
 * Reply MR[0] = status (0=ok), MR[1..3] = result
 */
#include "ipc_limits.h"

typedef unsigned long long u64;
typedef          long long i64;
extern i64 schild_sel4_recv(u64 src, u64 reply);
extern i64 schild_sel4_replyrecv(u64 src, u64 info, u64 reply);
extern i64 schild_sel4_reply_only(u64 reply, u64 info);
extern volatile u64 fs_reply_cptr;
extern volatile u64 fs_endpoint_cptr;
extern volatile u64 schild_recv_mr[4];
extern volatile u64 schild_reply_mr[4];
extern volatile u64 fs_daemon_alive_flag;

_Static_assert(sizeof(schild_recv_mr) == SCHILD_IPC_MR_BYTES,  "recv MR window must be 32 bytes");
_Static_assert(sizeof(schild_reply_mr) == SCHILD_IPC_MR_BYTES, "reply MR window must be 32 bytes");

void fs_daemon_main(void) {
    u64 ep = fs_endpoint_cptr;
    u64 reply = fs_reply_cptr;

    /* B1 fix pattern (from mls_server.c): no endpoint/reply → error flag + halt. */
    if (ep == 0 || reply == 0) {
        fs_daemon_alive_flag = 0xFF;
        for (;;) __asm__ volatile("pause");
    }

    /* Announce alive BEFORE Recv, so root task sees it after Yield. */
    fs_daemon_alive_flag = 0x01;

    schild_sel4_recv(ep, reply);

    for (;;) {
        u64 op = schild_recv_mr[0];
        u64 result = SCHILD_EBADMSG;   /* Stage 1: all ops EBADMSG */
        u64 result2 = 0;
        int fault_after_reply = 0;

        if (op == 0) {
            /* Stage 1 Init: no NVMe yet (Stage 2 will add NVMe ownership).
             * Report St_Ok (0) so the root task Call(init) returns cleanly. */
            result = 0;
        } else if (op == 99) {
            /* Crash-containment test: reply first, then fault on unmapped
             * 0xFFFFF000 so seL4 delivers a #PF to the FS fault endpoint. */
            result = 0;
            fault_after_reply = 1;
        }

        schild_reply_mr[0] = result;
        schild_reply_mr[1] = result2;
        schild_reply_mr[2] = 0;
        schild_reply_mr[3] = 0;

        if (fault_after_reply) {
            schild_sel4_reply_only(reply, 2ULL);
            *(volatile unsigned long long *)0x00000000FFFFF000ULL =
                0xDEADBEEFDEADBEEFULL;
            /* unreachable */
        }

        schild_sel4_replyrecv(ep, 2ULL, reply);
    }
}

volatile u64 fs_endpoint_cptr = 0;
volatile u64 fs_reply_cptr = 0;
