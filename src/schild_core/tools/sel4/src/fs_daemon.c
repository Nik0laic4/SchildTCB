/* Schild TCB — FS Daemon thread (audit H65/H86/H93).
 *
 * Stage 1: thread live + Recv loop.  Stage 2 (H86): NVMe ownership moved here.
 * Stage 3 (this file): full op dispatch to the Ada FS server (schild_fs_*).
 *
 * IPC buffer: dedicated 4KB frame at 0x530000 (set by Root Task).
 * MR layout: MR[0]=op, MR[1..3]=args; Reply MR[0]=status (0=ok), MR[1..3]=result.
 *   op 0 = Init, 1 = Open, 2 = Read, 3 = Write, 4 = Create, 5 = Append,
 *   6 = Get_Entry, 7 = Is_Mounted, 8 = Is_Read_Only, 9 = Delete, 99 = fault injection (test).
 * Large data (name, bytes, dir entry) via the shared frame @ 0x52A000.
 */
#include "ipc_limits.h"

typedef unsigned long long u64;
typedef          long long i64;
typedef unsigned int       u32;
extern i64 schild_sel4_recv(u64 src, u64 reply);
extern i64 schild_sel4_replyrecv(u64 src, u64 info, u64 reply);
extern i64 schild_sel4_reply_only(u64 reply, u64 info);
extern volatile u64 fs_reply_cptr;
extern volatile u64 fs_endpoint_cptr;
extern volatile u64 schild_recv_mr[4];
extern volatile u64 schild_reply_mr[4];
extern volatile u64 fs_daemon_alive_flag;

/* Ada exports (Schild_Fs_Server, Convention C).  out-params are pointers. */
extern u32 schild_fs_init(void);
extern u32 schild_fs_open(u32 name_len, u32* handle, u32* size);
extern u32 schild_fs_read(u32 handle, u32 offset, u32 len, u32* actual);
extern u32 schild_fs_write(u32 handle, u32 offset, u32 len, u32* new_off);
extern u32 schild_fs_create(u32 name_len, u32 size, u32* handle);
extern u32 schild_fs_append(u32 name_len, u32 len, u32* new_size);
extern u32 schild_fs_get_entry(u32 index);
extern u32 schild_fs_is_mounted(void);
extern u32 schild_fs_is_read_only(void);
extern u32 schild_fs_delete(u32 name_len);

_Static_assert(sizeof(schild_recv_mr) == SCHILD_IPC_MR_BYTES,  "recv MR window must be 32 bytes");
_Static_assert(sizeof(schild_reply_mr) == SCHILD_IPC_MR_BYTES, "reply MR window must be 32 bytes");

void fs_daemon_main(void) {
    /* H87: the endpoint/reply cptrs live in the shared DMA frame (0x52A000 in
     * this VSpace) — the root task writes them there; the .bss globals belong
     * to a different (root_task) ELF copy. */
    volatile u64 *sh = (volatile u64 *)0x52A000;
    u64 ep = sh[0];
    u64 reply = sh[1];

    /* B1 fix pattern (from mls_server.c): no endpoint/reply → error flag + halt. */
    if (ep == 0 || reply == 0) {
        sh[2] = 0xFF;
        for (;;) __asm__ volatile("pause");
    }

    /* Announce alive BEFORE Recv, so root task sees it after Yield. */
    sh[2] = 0x01;

    schild_sel4_recv(ep, reply);

    for (;;) {
        u64 op = schild_recv_mr[0];
        u64 a  = schild_recv_mr[1];
        u64 b  = schild_recv_mr[2];
        u64 c  = schild_recv_mr[3];
        u64 result  = SCHILD_EBADMSG;
        u64 result1 = 0;
        u64 result2 = 0;
        u64 result3 = 0;
        int fault_after_reply = 0;

        switch (op) {
        case 0:  /* Init: NVMe + SchildFS mount (single owner, H86). */
            result = (u64) schild_fs_init();
            break;
        case 1: {  /* Open: name_len (name in shared), -> handle, size */
            u32 h = 0, s = 0;
            result = (u64) schild_fs_open((u32)a, &h, &s);
            result1 = h; result2 = s;
            break;
        }
        case 2: {  /* Read: handle, offset, len -> actual_len (bytes in shared) */
            u32 act = 0;
            result = (u64) schild_fs_read((u32)a, (u32)b, (u32)c, &act);
            result1 = act;
            break;
        }
        case 3: {  /* Write: handle, offset, len (bytes in shared) -> new_offset */
            u32 no = 0;
            result = (u64) schild_fs_write((u32)a, (u32)b, (u32)c, &no);
            result1 = no;
            break;
        }
        case 4: {  /* Create: name_len (name in shared), size -> handle */
            u32 h = 0;
            result = (u64) schild_fs_create((u32)a, (u32)b, &h);
            result1 = h;
            break;
        }
        case 5: {  /* Append: name_len (name in shared), len (bytes in shared) -> new_size */
            u32 ns = 0;
            result = (u64) schild_fs_append((u32)a, (u32)b, &ns);
            result1 = ns;
            break;
        }
        case 6:  /* Get_Entry: index -> status (Dir_Entry in shared) */
            result = (u64) schild_fs_get_entry((u32)a);
            break;
        case 7:  /* Is_Mounted -> status */
            result = (u64) schild_fs_is_mounted();
            break;
        case 8:  /* Is_Read_Only -> status (0 = writable) */
            result = (u64) schild_fs_is_read_only();
            break;
        case 9:  /* Delete: name_len (name in shared) -> status */
            result = (u64) schild_fs_delete((u32)a);
            break;
        case 99: /* Crash-containment test: reply first, then fault on unmapped
                  * 0xFFFFF000 so seL4 delivers a #PF to the FS fault endpoint. */
            result = 0;
            fault_after_reply = 1;
            break;
        default:
            result = SCHILD_EBADMSG;
            break;
        }

        schild_reply_mr[0] = result;
        schild_reply_mr[1] = result1;
        schild_reply_mr[2] = result2;
        schild_reply_mr[3] = result3;

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

/* H87: FS entry/stack/cptr accessors (moved from schild_sel4_ipc.c — shim split). */
extern void  fs_daemon_entry(void);
extern char  fs_daemon_stack_top[];
u64 schild_fs_daemon_entry_addr(void) { return (u64)(void*)fs_daemon_entry; }
u64 schild_fs_daemon_stack_addr(void) { return (u64)fs_daemon_stack_top; }
void schild_set_fs_endpoint(u64 ep)   { ((volatile u64 *)0x52A000)[0] = ep; }
void schild_set_fs_reply(u64 rpl)     { ((volatile u64 *)0x52A000)[1] = rpl; }
u64  schild_get_fs_alive(void)        { return ((volatile u64 *)0x52A000)[2]; }
