/*
 * Copyright (C) 2026 Alexander Irganov
 * SPDX-License-Identifier: GPL-2.0-only
 */

/* Schild TCB Stage 5 — IPC buffer helpers for complex seL4 syscalls.
 *
 * seL4 x86_64 CONFIG_SYSCALL:
 *   - RSI = message info (label<<12 | capsUnwrapped<<9 | extraCaps<<7 | length)
 *   - MR[0..N-1] at IPC buffer word offset 1+N
 *   - Extra caps at IPC buffer word offset seL4_MsgMaxLength+2+N = 122+N
 *     (seL4_MsgMaxLength = 120 on x86_64, so byte offset = 976+N*8)
 *
 * Method labels (!MCS): UntypedRetype=1, TCBSetSpace=10
 * Object types: seL4_NotificationObject=3
 */

typedef unsigned long long u64;
typedef          long long i64;

volatile u64 schild_ipc_buf_addr = 0;
void schild_set_ipc_buf_addr(u64 addr) { schild_ipc_buf_addr = addr; }
i64 schild_test_ipc_writable(void) { volatile u64 *b=(volatile u64*)schild_ipc_buf_addr; u64 o=b[0]; b[0]=0xDEAD; __asm__("":::"memory"); i64 ok=b[0]==0xDEAD; b[0]=o; return ok; }

/* Safe IPC buffer init — reads BootInfo.IPC_Buffer WITHOUT writing.
 * Old Dump_Raw_BI wrote test cookie to buf[122] which COULD CORRUPT
 * BootInfo if IPC buffer overlaps BootInfo frame in physical memory.
 * This function ONLY reads — guaranteed safe. */
void schild_dump_raw_bootinfo(u64 bi_frame) {
    volatile u64 *b = (volatile u64*)bi_frame;
    schild_ipc_buf_addr = b[4];  /* BootInfo.IPC_Buffer at offset 0x20 */
}

#define MR_BASE 1
#define EXTRA_BASE 122

/* X86 arch invocation labels (offset from nSeL4ArchInvocationLabels).
 *
 * CONFIG_IOMMU inserts three extra labels (X86IOPageTableMap,
 * X86IOPageTableUnmap, X86PageMapIO) BEFORE X86PageMap / X86PageGetAddress,
 * shifting every later label.  The root task is built with -DSCHILD_IOMMU when
 * the kernel was built with KERNEL_IOMMU=ON. */
#ifdef SCHILD_IOMMU
#  define LBL_X86PAGEMAP         47   /* +2: two IOPT labels inserted */
#  define LBL_X86PAGEGETADDR     50   /* +3 */
#  define LBL_X86ASIDPOOLASSIGN  52   /* +3 */
#  define LBL_X86IRQIOAPIC       60   /* +3 */
#  define LBL_X86IRQMSI          61   /* +3 */
#  define LBL_X86IOPAGETABLEMAP  45   /* IOMMU-only */
#  define LBL_X86IOPAGETABLEUNMAP 46  /* IOMMU-only */
#  define LBL_X86PAGEMAPIO       49   /* IOMMU-only */
#else
#  define LBL_X86PAGEMAP         45
#  define LBL_X86PAGEGETADDR     47
#  define LBL_X86ASIDPOOLASSIGN  49
#  define LBL_X86IRQIOAPIC       57
#  define LBL_X86IRQMSI          58
#endif

static void set_mr(int n, u64 v) { volatile u64 *b=(volatile u64*)schild_ipc_buf_addr; b[MR_BASE+n]=v; }
static void set_ec(int n, u64 v) { volatile u64 *b=(volatile u64*)schild_ipc_buf_addr; b[EXTRA_BASE+n]=v; }

static i64 raw_send(u64 dest, u64 info) {
    i64 r;
    /* MR[0..3] must be in R10, R8, R9, R15 (hardware msg registers).
     * MR[4+] go via IPC buffer. */
    volatile u64 *b = (volatile u64*)schild_ipc_buf_addr;
    register u64 mr0 asm("r10") = b[1];
    register u64 mr1 asm("r8")  = b[2];
    register u64 mr2 asm("r9")  = b[3];
    register u64 mr3 asm("r15") = b[4];
    __asm__ volatile(
        "pushq %%rbx;"          /* save RBX on the stack (MCS: R12 = reply) */
        "movq %%rsp,%%rbx;"     /* user RSP for kernel */
        "movq $-1,%%rdx;"       /* SysCall */
        "syscall;"
        "movq %%rbx,%%rsp;"     /* restore RSP */
        "popq %%rbx;"           /* restore RBX */
        : "=S"(r)
        : "D"(dest), "S"(info),
          "r"(mr0), "r"(mr1), "r"(mr2), "r"(mr3)
        : "rdx","rcx","r11","memory");
    return r;
}

/* TCBSetSpace (label=11, MCS): 2 words + 3 extra caps.
 * MCS signature: fault_ep is a CPtr RESOLVED IN THE CALLER'S CSpace and COPIED
 * into the TCB (it must carry Write + Grant/GrantReply rights), NOT a word
 * resolved in the target TCB's CSpace as on non-MCS.
 *   MR[0]=cspace_root_data, MR[1]=vspace_root_data
 *   EC[0]=fault_ep, EC[1]=cspace_root, EC[2]=vspace_root */
i64 schild_sel4_tcb_set_fault_handler(u64 tcb, u64 fault_ep,
                                     u64 cspace, u64 cspace_data,
                                     u64 vspace, u64 vspace_data) {
    u64 info = (11ULL<<12)|(3ULL<<7)|2ULL;  /* label=11, extraCaps=3, len=2 */
    set_mr(0, cspace_data);   /* MR[0]=cspace_root_data (0=keep) */
    set_mr(1, vspace_data);   /* MR[1]=vspace_root_data (0=keep) */
    set_ec(0, fault_ep);      /* extra cap 0 = fault endpoint CPtr */
    set_ec(1, cspace);        /* extra cap 1 = CSpace root */
    set_ec(2, vspace);        /* extra cap 2 = VSpace root */
    return raw_send(tcb, info);
}

/* TCBSetIPCBuffer (label=10, MCS): 1 word + 1 extra cap (buffer frame) */
i64 schild_sel4_tcb_set_ipc_buffer(u64 tcb, u64 buf_cap, u64 buf_addr) {
    u64 info = (10ULL<<12)|(1ULL<<7)|1ULL;  /* label=10, extraCaps=1, len=1 */
    set_mr(0, buf_addr);
    set_ec(0, buf_cap);
    return raw_send(tcb, info);
}

/* Stage 7.6: get addresses of MLS server symbols */
extern void mls_server_entry(void);
extern char mls_stack_top[];
u64 schild_mls_entry_addr(void)  { return (u64)(void*)mls_server_entry; }
u64 schild_mls_stack_addr(void)  { return (u64)mls_stack_top; }

/* R3: Config Daemon entry/stack addresses (from config_daemon.S). */
extern void config_daemon_entry(void);
extern char config_stack_top[];
u64 schild_config_entry_addr(void) { return (u64)(void*)config_daemon_entry; }
u64 schild_config_stack_addr(void) { return (u64)config_stack_top; }

/* Stage 8.1D: NetServer endpoint setter + entry/stack addresses */
extern volatile u64 schild_net_endpoint_cptr;
void schild_set_net_endpoint(u64 ep) { schild_net_endpoint_cptr = ep; }
extern void netserver_entry(void);
extern char netserver_stack_top[];
u64 schild_netserver_entry_addr(void)  { return (u64)(void*)netserver_entry; }
u64 schild_netserver_stack_addr(void)  { return (u64)netserver_stack_top; }

/* Generic UntypedRetype for any object type */

i64 schild_sel4_retype_object(u64 untyped, u64 obj_type, u64 size_bits,
                             u64 root, u64 depth, u64 slot, u64 num) {
    u64 info = (1ULL<<12)|(1ULL<<7)|6ULL;
    set_mr(0, obj_type); set_mr(1, size_bits); set_mr(2, 0);
    set_mr(3, depth); set_mr(4, slot); set_mr(5, num);
    set_ec(0, root);
    return raw_send(untyped, info);
}

/* CNodeMint (label=22, MCS): copy a capability from src CNode to dest CNode.
 *   dest = dest CNode cap (the invoked capability), EC[0] = src CNode cap.
 *   MR[0]=dest_index, MR[1]=dest_depth, MR[2]=src_index, MR[3]=src_depth,
 *   MR[4]=rights, MR[5]=badge.
 * For the root CNode use src_depth = wordBits (64): its guard size is
 * wordBits - radix, so the total resolve depth is 64 bits. */
i64 schild_sel4_cnode_mint(u64 dest_cnode, u64 dest_index, u64 dest_depth,
                           u64 src_root, u64 src_index, u64 src_depth,
                           u64 rights, u64 badge) {
    u64 info = (22ULL<<12)|(1ULL<<7)|6ULL;  /* label=22, extraCaps=1, len=6 */
    set_mr(0, dest_index);
    set_mr(1, dest_depth);
    set_mr(2, src_index);
    set_mr(3, src_depth);
    set_mr(4, rights);
    set_mr(5, badge);
    set_ec(0, src_root);
    return raw_send(dest_cnode, info);
}

/* X86ASIDPoolAssign (label=49, MCS): bind a VSpace root (PML4) to an ASID.
 *   dest = ASID pool cap, EC[0] = VSpace root cap. No MRs. */
i64 schild_sel4_x86_asid_pool_assign(u64 pool, u64 vspace) {
    u64 info = (LBL_X86ASIDPOOLASSIGN<<12)|(1ULL<<7)|0ULL;  /* X86ASIDPoolAssign */
    set_ec(0, vspace);
    return raw_send(pool, info);
}

/* X86PDPTMap (label=39, MCS): map a PDPT into a VSpace root (PML4).
 *   dest = PDPT cap, EC[0] = PML4 (VSpace root). MR[0]=vaddr, MR[1]=attr. */
i64 schild_sel4_x86_pdpt_map(u64 pdpt, u64 vspace, u64 vaddr) {
    u64 info = (39ULL<<12)|(1ULL<<7)|2ULL;
    set_mr(0, vaddr);
    set_mr(1, 0ULL);
    set_ec(0, vspace);
    return raw_send(pdpt, info);
}

/* X86PageDirectoryMap (label=41, MCS): map a PD into a PDPT (via the VSpace root).
 *   dest = PD cap, EC[0] = PML4 (VSpace root). MR[0]=vaddr, MR[1]=attr. */
i64 schild_sel4_x86_page_directory_map(u64 pd, u64 vspace, u64 vaddr) {
    u64 info = (41ULL<<12)|(1ULL<<7)|2ULL;
    set_mr(0, vaddr);
    set_mr(1, 0ULL);
    set_ec(0, vspace);
    return raw_send(pd, info);
}

/* TCBResume (label=13, MCS): start the thread */
i64 schild_sel4_tcb_resume(u64 tcb) {
    u64 info = (13ULL<<12)|(0ULL<<7)|0ULL;
    return raw_send(tcb, info);
}

/* TCBWriteRegisters (label=3): set RIP+RSP for a suspended thread.
 * seL4 ABI: MR[0]=resume_target, MR[1]=count (number of registers),
 * MR[2..]=registers in seL4_UserContext order: rip, rsp, rflags, rax, ... */
i64 schild_sel4_tcb_write_registers(u64 tcb, u64 rip, u64 rsp) {
    u64 info = (3ULL<<12)|(0ULL<<7)|5ULL;  /* label=3, extraCaps=0, len=5 */
    set_mr(0, 0ULL);        /* resume_target=0 (resume separately) */
    set_mr(1, 3ULL);        /* count=3 registers */
    set_mr(2, rip);         /* FaultIP (RIP) */
    set_mr(3, rsp);         /* RSP */
    set_mr(4, 0x202ULL);    /* FLAGS: IF=1 */
    return raw_send(tcb, info);
}

/* Stage 7.6: set MLS endpoint CPtr */
extern volatile u64 mls_endpoint_cptr;
void schild_set_mls_endpoint(u64 ep) { mls_endpoint_cptr = ep; }

/* R3: set Config Daemon endpoint CPtr */
extern volatile u64 config_endpoint_cptr;
void schild_set_config_endpoint(u64 ep) { config_endpoint_cptr = ep; }

/* MCS reply-object CPtr setters.  Each server thread owns a reply object in
 * its CSpace; the root task writes the CPtr here before resuming the thread,
 * and the server passes it to Recv/ReplyRecv (the kernel stores the caller's
 * reply capability into it on a Call). */
extern volatile u64 net_reply_cptr;
void schild_set_net_reply(u64 r) { net_reply_cptr = r; }
extern volatile u64 mls_reply_cptr;
void schild_set_mls_reply(u64 r) { mls_reply_cptr = r; }
extern volatile u64 config_reply_cptr;
void schild_set_config_reply(u64 r) { config_reply_cptr = r; }

/* Reply MR[0..3] captured by schild_sel4_call (seL4 x86_64: delivered in R10/R8/R9/R15) */
extern volatile u64 schild_call_mr[4];

/* ─── Stage 7.7: PageMap + dedicated IPC buffer for MLS server ─── */

/* X86PageMap (label=45, MCS): map a 4K frame into a VSpace.
 *   MR[0]=vaddr, MR[1]=rights(3=RW), MR[2]=attr(0)
 *   extra cap 0 = VSpace root
 *   dest = page frame cap */
i64 schild_sel4_x86_page_map(u64 page, u64 vspace, u64 vaddr) {
    u64 info = (LBL_X86PAGEMAP<<12)|(1ULL<<7)|3ULL;
    set_mr(0, vaddr);
    set_mr(1, 3ULL);        /* seL4_ReadWrite */
    set_mr(2, 0ULL);        /* VM attributes = default */
    set_ec(0, vspace);
    return raw_send(page, info);
}

/* X86PageMap (label=45, MCS) with explicit VM rights (CapRights layout:
 * bit0=Write, bit1=Read): 3=ReadWrite, 2=ReadOnly.
 * R4 directional mapping: producer page RW, consumer page RO (and vice versa). */
i64 schild_sel4_x86_page_map_rights(u64 page, u64 vspace, u64 vaddr, u64 rights) {
    u64 info = (LBL_X86PAGEMAP<<12)|(1ULL<<7)|3ULL;
    set_mr(0, vaddr);
    set_mr(1, rights);      /* seL4_ReadWrite=3 or seL4_CanRead=2 */
    set_mr(2, 0ULL);
    set_ec(0, vspace);
    return raw_send(page, info);
}

/* X86PageTableMap (label=43, MCS): map a page-table object into a VSpace.
 *   MR[0]=vaddr, MR[1]=attr(0)
 *   extra cap 0 = VSpace root
 *   dest = page-table cap */
i64 schild_sel4_x86_page_table_map(u64 pt, u64 vspace, u64 vaddr) {
    u64 info = (43ULL<<12)|(1ULL<<7)|2ULL;
    set_mr(0, vaddr);
    set_mr(1, 0ULL);        /* VM attributes = default */
    set_ec(0, vspace);
    return raw_send(pt, info);
}

/* X86PageGetAddress (label=47, MCS): query a frame's physical address.
 * Call semantics: reply MR[0] holds the physical address, captured by the
 * inline asm into schild_call_mr[0].  Read it with schild_read_ipc_mr0(). */
i64 schild_sel4_x86_page_get_address(u64 page) {
    u64 info = (LBL_X86PAGEGETADDR<<12)|(0ULL<<7)|0ULL;  /* X86PageGetAddress */
    i64 r;
    __asm__ volatile(
        "movq %%rbx,%%r12\n\t"
        "movq %%rsp,%%rbx\n\t"
        "movq $-1,%%rdx\n\t"       /* SysCall (-1) = Call */
        "syscall\n\t"
        "movq %%rbx,%%rsp\n\t"
        "movq %%r10,schild_call_mr+0(%%rip)\n\t"
        "movq %%r12,%%rbx"
        : "=S"(r)
        : "D"(page), "S"(info)
        : "rdx","rcx","r11","r12","memory");
    return r;
}

/* Dedicated IPC buffer address for the MLS server thread.
 * Set by Ada code before MLS thread is resumed. */
volatile u64 mls_ipc_buf_addr = 0;
void schild_set_mls_ipc_buf(u64 addr) { mls_ipc_buf_addr = addr; }

/* Return root task's IPC buffer virtual address (for sharing). */
u64 schild_get_ipc_buf_addr(void) { return schild_ipc_buf_addr; }

/* ─── Stage 7.7: IPC Call (Send + wait for Reply) ───
 *
 * SysCall (-1) to an endpoint performs a Call: send MRs, block
 * until receiver Replies.  On return the reply MessageInfo is in
 * RSI (seL4 x86_64 ABI) and the reply MR[0] is in the IPC buffer
 * at offset 1.
 *
 * Returns: reply MessageInfo (RSI).  MR[0] reply at b[1] on success.
 */
i64 schild_sel4_call(u64 dest, u64 mr0, u64 mr1) {
    i64 r;
    volatile u64 *b = (volatile u64*)schild_ipc_buf_addr;
    b[1] = mr0;
    b[2] = mr1;
    register u64 _mr0 asm("r10") = mr0;
    register u64 _mr1 asm("r8")  = mr1;
    register u64 _mr2 asm("r9")  = 0;
    register u64 _mr3 asm("r15") = 0;
    u64 info = 2ULL;  /* length=2 */
    __asm__ volatile(
        "movq %%rbx,%%r12\n\t"
        "movq %%rsp,%%rbx\n\t"     /* user RSP for kernel        */
        "movq $-1,%%rdx\n\t"       /* SysCall (-1) = Call        */
        "syscall\n\t"
        "movq %%rbx,%%rsp\n\t"     /* restore RSP after reply    */
        /* Capture the reply MR[0..3]: seL4 x86_64 delivers them in
         * R10/R8/R9/R15, NOT in the IPC buffer. */
        "movq %%r10,schild_call_mr+0(%%rip)\n\t"
        "movq %%r8, schild_call_mr+8(%%rip)\n\t"
        "movq %%r9, schild_call_mr+16(%%rip)\n\t"
        "movq %%r15,schild_call_mr+24(%%rip)\n\t"
        "movq %%r12,%%rbx"
        : "=S"(r)                   /* reply MessageInfo in RSI  */
        : "D"(dest), "S"(info),
          "r"(_mr0), "r"(_mr1), "r"(_mr2), "r"(_mr3)
        : "rdx","rcx","r11","r12","memory");
    return r;
}

/* Read reply MR[0] after a Call.  The reply MR[0] is delivered in R10 on
 * x86_64 and captured by schild_sel4_call into schild_call_mr[0]. */
u64 schild_read_ipc_mr0(void) {
    return schild_call_mr[0];
}

/* Read reply MR[1] after a Call (captured in R8 by schild_sel4_call). */
u64 schild_read_ipc_mr1(void) {
    return schild_call_mr[1];
}

/* Read recv MR[0] captured by the Wait/Recv stub (e.g. the SC badge carried in
 * a timeout fault: seL4_Fault_Timeout puts the SC badge in MR[0]). */
extern volatile u64 schild_recv_mr[4];
u64 schild_read_recv_mr0(void) {
    return schild_recv_mr[0];
}

/* ─── Stage 8.3: e1000e IRQ via Notification ───────────────────────────── */

/* IRQControl_GetIOAPIC (X86IRQIssueIRQHandlerIOAPIC, label=57, MCS):
 *   Create an IRQHandler cap for an IOAPIC-routed IRQ.
 *   MR[0]=dest index, MR[1]=depth, MR[2]=ioapic, MR[3]=pin (GSI),
 *   MR[4]=level (1=level-triggered), MR[5]=polarity (1=active-low),
 *   MR[6]=irq (relative to irq_user_min=16 → vector = irq+16+0x20).
 *   EC[0] = root CNode (destination). */
i64 schild_sel4_irq_control_get_ioapic(u64 irq_control, u64 index, u64 depth,
                                       u64 ioapic, u64 pin, u64 level,
                                       u64 polarity, u64 irq, u64 root) {
    u64 info = (LBL_X86IRQIOAPIC<<12)|(1ULL<<7)|7ULL;  /* X86IRQIssueIRQHandlerIOAPIC */
    set_mr(0, index);
    set_mr(1, depth);
    set_mr(2, ioapic);
    set_mr(3, pin);
    set_mr(4, level);
    set_mr(5, polarity);
    set_mr(6, irq);
    set_ec(0, root);
    return raw_send(irq_control, info);
}

/* IRQControl_GetMSI (X86IRQIssueIRQHandlerMSI, label=58, MCS):
 *   Create an IRQHandler cap for an MSI (Message Signaled Interrupt).
 *   MR[0]=dest index, MR[1]=depth, MR[2]=pci_bus, MR[3]=pci_dev,
 *   MR[4]=pci_func, MR[5]=handle (MSI data value), MR[6]=irq (rel to
 *   irq_user_min=16).  EC[0] = root CNode (destination). */
i64 schild_sel4_irq_control_get_msi(u64 irq_control, u64 index, u64 depth,
                                     u64 pci_bus, u64 pci_dev, u64 pci_func,
                                     u64 handle, u64 irq, u64 root) {
    u64 info = (LBL_X86IRQMSI<<12)|(1ULL<<7)|7ULL;  /* X86IRQIssueIRQHandlerMSI */
    set_mr(0, index);
    set_mr(1, depth);
    set_mr(2, pci_bus);
    set_mr(3, pci_dev);
    set_mr(4, pci_func);
    set_mr(5, handle);
    set_mr(6, irq);
    set_ec(0, root);
    return raw_send(irq_control, info);
}

/* IRQHandler_SetNotification (label=28): bind an IRQ handler to a notification.
 *   EC[0] = notification cap (must have send rights). No MRs. */
i64 schild_sel4_irq_handler_set_notification(u64 irq_handler, u64 ntfn) {
    u64 info = (28ULL<<12)|(1ULL<<7)|0ULL;  /* label=28, extraCaps=1, len=0 */
    set_ec(0, ntfn);
    return raw_send(irq_handler, info);
}

/* IRQHandler_Ack (label=27): acknowledge the IRQ (unmask it). No MRs/caps. */
i64 schild_sel4_irq_handler_ack(u64 irq_handler) {
    u64 info = (27ULL<<12)|(0ULL<<7)|0ULL;  /* label=27, extraCaps=0, len=0 */
    return raw_send(irq_handler, info);
}

/* ─── MCS scheduling-context helpers ─────────────────────────────────────── */

/* SchedControl_ConfigureFlags (label=33, MCS): populate a scheduling context
 * with a CPU budget.  budget/period are microseconds; budget == period yields
 * a round-robin context.  extra_refills=0 for periodic behaviour.
 *   MR[0]=budget, MR[1]=period, MR[2]=extra_refills, MR[3]=badge, MR[4]=flags
 *   EC[0]=schedcontext */
i64 schild_sel4_schedcontrol_configureflags(u64 schedcontrol, u64 schedcontext,
                                            u64 budget, u64 period,
                                            u64 extra_refills, u64 badge,
                                            u64 flags) {
    u64 info = (33ULL<<12)|(1ULL<<7)|5ULL;  /* label=33, extraCaps=1, len=5 */
    set_mr(0, budget);
    set_mr(1, period);
    set_mr(2, extra_refills);
    set_mr(3, badge);
    set_mr(4, flags);
    set_ec(0, schedcontext);
    return raw_send(schedcontrol, info);
}

/* SchedContext_Bind (label=34, MCS): bind a TCB (or notification) to a
 * scheduling context.  EC[0] = the TCB cap to bind.  No MRs. */
i64 schild_sel4_schedcontext_bind(u64 schedcontext, u64 tcb) {
    u64 info = (34ULL<<12)|(1ULL<<7)|0ULL;  /* label=34, extraCaps=1, len=0 */
    set_ec(0, tcb);
    return raw_send(schedcontext, info);
}

/* TCBSetTimeoutEndpoint (label=9, MCS): set the endpoint that receives timeout
 * faults when this thread's scheduling-context budget is exhausted (sporadic,
 * budget < period).  EC[0] = timeout fault endpoint.  No MRs. */
i64 schild_sel4_tcb_set_timeout_endpoint(u64 tcb, u64 timeout_ep) {
    u64 info = (9ULL<<12)|(1ULL<<7)|0ULL;  /* label=9, extraCaps=1, len=0 */
    set_ec(0, timeout_ep);
    return raw_send(tcb, info);
}

/* ─── P1 (R10): serializing timestamp counter for the IPC benchmark ──────
 * RDTSCP is serializing (available on nehalem+, the target microarch). */
u64 schild_rdtsc(void) {
    unsigned int lo, hi, aux;
    __asm__ volatile("rdtscp" : "=a"(lo), "=d"(hi), "=c"(aux) : : "memory");
    return ((u64)hi << 32) | lo;
}

