/* Schild TCB R3 — Config Daemon process (isolated fault domain).
 *
 * Receives IPC on its configured endpoint, validates configuration requests,
 * and replies with the result. This gives the config daemon its own fault
 * domain: a fault here lands on the config fault notification, not the root
 * task. The SPARK-verified Validate_Config runs in the root task's verified
 * path; this process is the isolated runtime scaffold.
 *
 * MR layout:  MR[0]=op (0=validate, 1=commit, 2=rollback)  MR[1]=level
 * Reply:       MR[0]=result (0=denied, 1=allowed)
 */
#include "ipc_limits.h"

typedef unsigned long long u64;
typedef          long long i64;
extern i64 schild_sel4_recv(u64 src, u64 reply);
extern i64 schild_sel4_replyrecv(u64 src, u64 info, u64 reply);
extern i64 schild_sel4_reply_only(u64 reply, u64 info);
extern volatile u64 config_reply_cptr;
extern volatile u64 schild_recv_mr[4];
extern volatile u64 schild_reply_mr[4];

/* Verified Ada gate (schild_config_daemon.Config_Authorize_Op). 1 = allowed, 0 = denied. */
extern unsigned int schild_config_authorize_op(unsigned int op, unsigned int level);

/* Shared-layout invariants: the C MR window must match the Ada/SPARK view. */
_Static_assert(sizeof(schild_recv_mr) == SCHILD_IPC_MR_BYTES,  "recv MR window must be 32 bytes");
_Static_assert(sizeof(schild_reply_mr) == SCHILD_IPC_MR_BYTES, "reply MR window must be 32 bytes");

void config_daemon_main(void) {
    extern volatile u64 config_endpoint_cptr;
    u64 endpoint = config_endpoint_cptr;
    u64 reply = config_reply_cptr;

    if (endpoint == 0 || reply == 0) {
        extern char config_alive_flag;
        config_alive_flag = 0xFF;  /* error marker */
        for (;;) __asm__ volatile("pause");
    }

    schild_sel4_recv(endpoint, reply);

    for (;;) {
        u64 op    = schild_recv_mr[0];
        u64 level = schild_recv_mr[1];

        u64 result;
        int fault_after_reply = 0;
        int spin_after_reply = 0;
        if (op == 99) {
            /* Crash-containment test: reply first, then fault on unmapped
             * 0xFFFFF000 so seL4 delivers a #PF to the Config fault endpoint
             * (slot 526). */
            result = 0;
            fault_after_reply = 1;
        } else if (op == 98) {
            /* B.6 timeout test: reply first, then spin to exhaust the sporadic
             * scheduling-context budget; the kernel delivers a seL4_Fault_Timeout
             * to the shared timeout endpoint (slot 215). */
            result = 0;
            spin_after_reply = 1;
        } else if (op > 2) {
            result = SCHILD_EBADMSG;   /* unknown config operation */
        } else if (level > 4) {
            result = SCHILD_EBADMSG;   /* level outside 0..4 */
        } else {
            /* Delegate the access decision to the verified Ada gate
             * (Schild_Config_Daemon.Config_Authorize_Op) instead of an
             * unverified inline C check. */
            result = (u64)schild_config_authorize_op((unsigned int)op,
                                                      (unsigned int)level);
        }

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

        if (spin_after_reply) {
            schild_sel4_reply_only(reply, 1ULL);
            for (;;) { }   /* exhaust the sporadic budget -> timeout fault */
        }

        schild_sel4_replyrecv(endpoint, 1ULL, reply);  /* reply + next recv */
    }
}
volatile u64 config_endpoint_cptr = 0;
volatile u64 config_reply_cptr = 0;
