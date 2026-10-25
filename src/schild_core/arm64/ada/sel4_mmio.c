/* Copyright (C) 2026 Alexander Irganov
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Schild TCB -- seL4 AArch64 MMIO mapping shim.
 *
 * Maps a device MMIO region into the root-task VSpace and reads a virtio-net
 * device's MAC address.  This is the minimal seL4 object-management sequence:
 *   BootInfo -> find device untyped -> UntypedRetype -> ARM_Page_Map -> read.
 *
 * Syscall ABI (AArch64): "svc #0", x7 = syscall id, x0-x5 = args, x6 = MCS
 * reply.  seL4_Call (seL4_SysCall = -1): x0=dest, x1=info, x2..x5=MR0..3;
 * the reply message info comes back in x1 (its label is the error code).
 *
 * Message info: (label << 12) | (capsUnwrapped << 9) | (extraCaps << 7) | length.
 * IPC buffer: MR[0..N] at word offset 1..N; extra caps at word offset
 *   seL4_MsgMaxLength + 2 + N = 122 + N (seL4_MsgMaxLength = 120).
 *
 * Invocation labels (from the generated libsel4 headers): UntypedRetype = 1,
 *   ARMPageMap = 40.  Object types: seL4_ARM_SmallPageObject = 7.
 * Caps: seL4_CapInitThreadCNode = 2, seL4_CapInitThreadVSpace = 3.
 * Rights: seL4_ReadWrite = (0<<3)|(0<<2)|(1<<1)|(1<<0) = 3.
 */

#include "virtio_net.h"

extern u64 rt_bootinfo;      /* saved by root_start.S */
static u64 ipc_buf;          /* BootInfo.ipcBuffer */
static u64 next_slot;        /* next free CNode slot for retype targets */

/* ---- IPC buffer helpers ---- */
static inline void set_mr(int n, u64 v)  { ((volatile u64 *)ipc_buf)[1 + n]   = v; }
static inline void set_cap(int n, u64 v) { ((volatile u64 *)ipc_buf)[122 + n] = v; }

/* ---- seL4_Call (seL4_SysCall = -1) ---- */
static inline u64 sel4_call(u64 dest, u64 info, u64 mr0, u64 mr1, u64 mr2, u64 mr3)
{
    register u64 x0 asm("x0") = dest;
    register u64 x1 asm("x1") = info;
    register u64 x2 asm("x2") = mr0;
    register u64 x3 asm("x3") = mr1;
    register u64 x4 asm("x4") = mr2;
    register u64 x5 asm("x5") = mr3;
    register u64 x7 asm("x7") = -1;   /* seL4_SysCall (non-MCS) */
    __asm__ volatile("svc #0"
                     : "+r"(x0), "+r"(x1), "+r"(x2), "+r"(x3), "+r"(x4), "+r"(x5)
                     : "r"(x7)
                     : "memory");
    return x1;   /* reply message info word; label = error code (0 = ok) */
}

static inline u64 info_label(u64 info) { return (info >> 12) & 0xfffff; }

/* ---- BootInfo layout (AArch64, MCS) ---- */
#define BI_IPCBUF         32    /* seL4_Word ipcBuffer */
#define BI_UNTYPED_START  152   /* untyped.start (non-MCS: no schedcontrol) */
#define BI_UNTYPED_END    160   /* untyped.end */
#define BI_UNTYPED_LIST   168   /* untypedList[] */
/* seL4_UntypedDesc: paddr (u64) @0, sizeBits (u8) @8, isDevice (u8) @9; 16 B. */

static inline u64 bi_word(u64 bi, int off) { return ((volatile u64 *)(bi + off))[0]; }

/* Retype an untyped (device or RAM) into one 2 MiB large page, placing the cap
 * at `target_slot` of the root CNode. */
static u64 retype_large_page(u64 untyped_cap, u64 target_slot)
{
    u64 info = (1ULL << 12) | (1ULL << 7) | 6ULL;  /* UntypedRetype: label=1, extraCaps=1, len=6 */
    set_cap(0, 2);                                 /* EC[0] = root CNode */
    set_mr(4, target_slot);                        /* node_offset */
    set_mr(5, 1);                                  /* num_objects */
    /* MR[0]=type(8)=LargePage, MR[1]=size_bits(21), MR[2]=node_index(0),
       MR[3]=node_depth(0: root CNode used directly) */
    return info_label(sel4_call(untyped_cap, info, 8, 21, 0, 0));
}

/* Map a small page into the root VSpace at `vaddr`. */
static u64 map_page(u64 page_cap, u64 vaddr)
{
    u64 info = (40ULL << 12) | (1ULL << 7) | 3ULL; /* ARMPageMap: label=40, extraCaps=1, len=3 */
    set_cap(0, 3);                                 /* EC[0] = VSpace */
    /* MR[0]=vaddr, MR[1]=rights(3=ReadWrite), MR[2]=attr(0) */
    return info_label(sel4_call(page_cap, info, vaddr, 3, 0, 0));
}

/* =============================================================================
 * virtio IRQ -> seL4 Notification routing.
 *
 * The virtio-net device is on virtio-mmio slot 31 (0x0a00_3e00), whose GIC
 * interrupt is SPI 47 = GIC IRQ 32 + 47 = 79 (qemu-arm-virt, NUM_PPI=32).
 * We bind that IRQ to a seL4 notification (badged with 79).  A dedicated
 * waiter thread blocks on that notification (seL4_Wait), Acks the IRQ, and
 * signals a second notification that the main thread blocks on; the main
 * thread then drains the used ring.  No busy-polling.
 * ============================================================================= */

#define VIRTIO_MMIO_IRQ 79
/* Depth for CNode ops / IRQControl_Get on the root CNode.  The root CNode is
 * created with radix = CONFIG_ROOT_CNODE_SIZE_BITS (13) and guard size =
 * wordBits - 13 (51), so the full slot is resolved at depth = wordBits. */
#define ROOT_CNODE_DEPTH 64

/* File-scope caps for the IRQ notification path (populated by virtio_net_init). */
static u64 net_irq_ntfn;      /* badged IRQ notification cap (CPtr) */
static u64 net_irq_handler;   /* IRQ handler cap (CPtr) */
static u64 net_main_ntfn;     /* waiter -> main "IRQ arrived" notification */
static u32 net_irq_count;     /* IRQs delivered through the notification */

/* IRQControl_Get: label IRQIssueIRQHandler=26, extraCaps=1 (root CNode), len=3. */
static u64 sel4_irq_control_get(u64 irq_control, u64 irq, u64 index, u64 depth)
{
    u64 info = (26ULL << 12) | (1ULL << 7) | 3ULL;
    set_cap(0, 2);   /* EC[0] = root CNode */
    return info_label(sel4_call(irq_control, info, irq, index, depth, 0));
}

/* IRQHandler_SetNotification: label IRQSetIRQHandler=28, extraCaps=1, len=0. */
static u64 sel4_irq_handler_set_ntfn(u64 irq_handler, u64 ntfn)
{
    u64 info = (28ULL << 12) | (1ULL << 7) | 0ULL;
    set_cap(0, ntfn);
    return info_label(sel4_call(irq_handler, info, 0, 0, 0, 0));
}

/* IRQHandler_Ack: label IRQAckIRQ=27, extraCaps=0, len=0. */
static u64 sel4_irq_handler_ack(u64 irq_handler)
{
    u64 info = (27ULL << 12) | 0ULL;
    return info_label(sel4_call(irq_handler, info, 0, 0, 0, 0));
}

/* CNode_Mint: label CNodeMint=21, extraCaps=1 (src_root), len=6.  Mints a
 * badged cap from src_index (in src_cnode) into dest_index (in dest_cnode). */
static u64 sel4_cnode_mint(u64 dest_cnode, u64 dest_index, u64 dest_depth,
                           u64 src_cnode, u64 src_index, u64 src_depth,
                           u64 rights, u64 badge)
{
    u64 info = (21ULL << 12) | (1ULL << 7) | 6ULL;
    set_cap(0, src_cnode);    /* EC[0] = src_root CNode */
    set_mr(4, rights);
    set_mr(5, badge);
    return info_label(sel4_call(dest_cnode, info, dest_index, dest_depth, src_index, src_depth));
}

/* Track RAM untyped slots already carved, so the notification and the DMA
 * frame do not compete for the same untyped. */
static u64 used_ram_untyped[8];
static int used_ram_untyped_count;

static void mark_untyped_used(u64 slot)
{
    if (used_ram_untyped_count < 8)
        used_ram_untyped[used_ram_untyped_count++] = slot;
}

static int untyped_is_used(u64 slot)
{
    int i;
    for (i = 0; i < used_ram_untyped_count; i++)
        if (used_ram_untyped[i] == slot) return 1;
    return 0;
}

/* Find a RAM (non-device) untyped with at least 2^min_bits bytes, not already
 * used.  Returns the slot, or (u64)-1. */
static u64 find_ram_untyped(u32 min_bits)
{
    u64 bi = rt_bootinfo;
    u64 start = bi_word(bi, BI_UNTYPED_START);
    u64 end = bi_word(bi, BI_UNTYPED_END);
    u64 slot;

    for (slot = start; slot < end; slot++) {
        u64 desc = bi + BI_UNTYPED_LIST + (slot - start) * 16;
        u64 sizebits = ((volatile unsigned char *)(desc + 8))[0];
        u64 isdev = ((volatile unsigned char *)(desc + 9))[0];
        if (!isdev && sizebits >= min_bits && !untyped_is_used(slot))
            return slot;
    }
    return (u64)-1;
}

/* Retype a notification object (32 bytes, seL4_NotificationBits=5 non-MCS)
 * from a fresh RAM untyped. */
static u64 retype_notification(u64 untyped_cap, u64 target_slot)
{
    u64 info = (1ULL << 12) | (1ULL << 7) | 6ULL;  /* UntypedRetype: label=1, extraCaps=1, len=6 */
    set_cap(0, 2);
    set_mr(4, target_slot);
    set_mr(5, 1);
    return info_label(sel4_call(untyped_cap, info, 3 /* NotificationObject */, 5, 0, 0));
}

/* seL4_Signal (seL4_SysSend = -3): empty signal on a notification. */
static inline void sel4_signal(u64 dest)
{
    register u64 x0 asm("x0") = dest;
    register u64 x1 asm("x1") = 0;   /* empty message info */
    register u64 x7 asm("x7") = -3;  /* seL4_SysSend */
    __asm__ volatile("svc #0" : "+r"(x0), "+r"(x1) : "r"(x7) : "memory");
}

/* seL4_Wait (seL4_SysRecv = -5): blocking receive on a notification.  Returns
 * the badge once the notification is signaled. */
static inline u64 sel4_wait(u64 src)
{
    register u64 x0 asm("x0") = src;
    register u64 x1 asm("x1");
    register u64 x2 asm("x2");
    register u64 x3 asm("x3");
    register u64 x4 asm("x4");
    register u64 x5 asm("x5");
    register u64 x7 asm("x7") = -5;   /* seL4_SysRecv */
    __asm__ volatile("svc #0"
                     : "+r"(x0), "=r"(x1), "=r"(x2), "=r"(x3), "=r"(x4), "=r"(x5)
                     : "r"(x7)
                     : "memory");
    return x0;
}

/* TCB_Configure: label TCBConfigure=5, extraCaps=3 (cspace/vspace/bufferFrame),
 * len=4 (non-MCS: MR0=fault_ep, MR1=cspace_root_data, MR2=vspace_root_data,
 * MR3=buffer). */
static u64 sel4_tcb_configure(u64 tcb, u64 fault_ep, u64 cspace_root, u64 cspace_root_data,
                              u64 vspace_root, u64 vspace_root_data, u64 buffer, u64 buffer_frame)
{
    u64 info = (5ULL << 12) | (3ULL << 7) | 4ULL;
    set_cap(0, cspace_root);
    set_cap(1, vspace_root);
    set_cap(2, buffer_frame);
    return info_label(sel4_call(tcb, info, fault_ep, cspace_root_data, vspace_root_data, buffer));
}

/* TCB_WriteRegisters: label TCBWriteRegisters=3, extraCaps=0, len=4.  Writes
 * pc + sp (count=2) and resumes the thread. */
static u64 sel4_tcb_write_registers(u64 tcb, u64 pc, u64 sp)
{
    u64 info = (3ULL << 12) | 0ULL | 4ULL;
    return info_label(sel4_call(tcb, info, 1 /* resume */, 2 /* count */, pc, sp));
}

/* Retype a TCB object (seL4_TCBBits=11 non-MCS) from a fresh RAM untyped. */
static u64 retype_tcb(u64 untyped_cap, u64 target_slot)
{
    u64 info = (1ULL << 12) | (1ULL << 7) | 6ULL;  /* UntypedRetype: label=1, extraCaps=1, len=6 */
    set_cap(0, 2);
    set_mr(4, target_slot);
    set_mr(5, 1);
    return info_label(sel4_call(untyped_cap, info, 1 /* TCBObject */, 11 /* TCBBits */, 0, 0));
}

/* Retype a CNode object (seL4_CapTableObject=4) with `radix` slot bits.  The
 * size_bits argument is the radix; getObjectSize computes seL4_SlotBits+radix. */
static u64 retype_cnode(u64 untyped_cap, u64 target_slot, u32 radix)
{
    u64 info = (1ULL << 12) | (1ULL << 7) | 6ULL;
    set_cap(0, 2);
    set_mr(4, target_slot);
    set_mr(5, 1);
    return info_label(sel4_call(untyped_cap, info, 4 /* CapTableObject */, radix, 0, 0));
}

/* Map the physical device region at `phys` into the VSpace at `vaddr`.
 * Returns `vaddr` on success, 0 on failure. */
u64 schild_map_mmio(u64 phys, u64 vaddr)
{
    u64 bi = rt_bootinfo;
    u64 start, end, slot;

    ipc_buf = bi_word(bi, BI_IPCBUF);
    start   = bi_word(bi, BI_UNTYPED_START);
    end     = bi_word(bi, BI_UNTYPED_END);
    next_slot = end;         /* first free slot after the untyped region */

    /* 1. Find a device untyped covering `phys`. */
    for (slot = start; slot < end; slot++) {
        u64 desc     = bi + BI_UNTYPED_LIST + (slot - start) * 16;
        u64 paddr    = ((volatile u64 *)(desc + 0))[0];
        u64 sizebits = ((volatile unsigned char *)(desc + 8))[0];
        u64 isdev    = ((volatile unsigned char *)(desc + 9))[0];
        u64 size     = 1ULL << sizebits;

        if (isdev && phys >= paddr && phys < paddr + size) {
            /* 2. Retype into a large page at the first slot after the untyped
             *    region, then 3. map it into the VSpace.  The mapped region
             *    starts at `paddr`, so return the VA of `phys`. */
            u64 target = next_slot++;
            if (retype_large_page(slot, target) != 0) return 0;
            if (map_page(target, vaddr) != 0) return 0;
            return vaddr + (phys - paddr);
        }
    }
    return 0;   /* no device untyped covers `phys` */
}

/* Map the virtio-net device (first virtio-mmio slot @ 0x0a00_3e00) once and
 * cache its register base. */
static volatile u32 *dev_regs;

static volatile u32 *get_dev_regs(void)
{
    if (dev_regs == 0) {
        u64 va = schild_map_mmio(0x0a003e00ULL, 0x200000ULL);
        if (va == 0) return 0;
        dev_regs = (volatile u32 *)va;
    }
    return dev_regs;
}

/* Read the virtio-net MAC.  Returns the 6-byte MAC in the low 48 bits, or 0. */
u64 schild_virtio_mac(void)
{
    volatile u32 *regs = get_dev_regs();
    u64 mac = 0;
    u32 m0, m1;
    int i;

    if (regs == 0) return 0;
    if (regs[0] != 0x74726976u) return 0;   /* MagicValue ("virt") */

    /* Bring the device into ACKNOWLEDGE|DRIVER before reading the config space. */
    regs[0x70 / 4] = 0;                     /* Status = reset (offset 0x70) */
    regs[0x70 / 4] = 1;                     /* Status = ACKNOWLEDGE */
    regs[0x70 / 4] = 3;                     /* Status = ACKNOWLEDGE | DRIVER */

    /* virtio-net config space: mac[0..3] at 0x100, mac[4..5] at 0x104. */
    m0 = regs[0x100 / 4];
    m1 = regs[0x104 / 4];
    for (i = 0; i < 4; i++) mac |= (u64)((m0 >> (8 * i)) & 0xff) << (8 * i);
    for (i = 0; i < 2; i++) mac |= (u64)((m1 >> (8 * i)) & 0xff) << (8 * (4 + i));
    return mac;
}

/* =============================================================================
 * virtio-net virtqueue driver (TX test).
 * ============================================================================= */

/* virtio-mmio register offsets (modern layout, virtio spec v1.0+). */
#define VMMIO_DEVICE_FEATURES   0x010
#define VMMIO_DRIVER_FEATURES   0x020
#define VMMIO_QUEUE_SEL         0x030
#define VMMIO_QUEUE_NUM_MAX     0x034
#define VMMIO_QUEUE_NUM         0x038
#define VMMIO_QUEUE_ALIGN       0x03c   /* legacy (Version=1) */
#define VMMIO_QUEUE_PFN         0x040   /* legacy (Version=1) */
#define VMMIO_QUEUE_READY       0x044
#define VMMIO_QUEUE_NOTIFY      0x050
#define VMMIO_STATUS            0x070
#define VMMIO_ISR               0x060
#define VMMIO_QUEUE_DESC_LOW    0x080
#define VMMIO_QUEUE_DESC_HIGH   0x084
#define VMMIO_QUEUE_DRIVER_LOW  0x090
#define VMMIO_QUEUE_DRIVER_HIGH 0x094
#define VMMIO_QUEUE_DEVICE_LOW  0x0a0
#define VMMIO_QUEUE_DEVICE_HIGH 0x0a4

#define VIRTIO_STATUS_ACKNOWLEDGE 1
#define VIRTIO_STATUS_DRIVER      2
#define VIRTIO_STATUS_DRIVER_OK   4
#define VIRTIO_STATUS_FEATURES_OK 8

#define VQ_NUM 4

/* Split-virtqueue structures. */
struct vring_desc {
    u64 addr;
    u32 len;
    u16 flags;
    u16 next;
};
struct vring_avail {
    u16 flags;
    u16 idx;
    u16 ring[VQ_NUM];
};
struct vring_used_elem {
    u32 id;
    u32 len;
};
struct vring_used {
    u16 flags;
    u16 idx;
    struct vring_used_elem ring[VQ_NUM];
};

static inline u32 mmio32(volatile u32 *b, u32 off)   { return b[off / 4]; }
static inline void mmio32w(volatile u32 *b, u32 off, u32 v) { b[off / 4] = v; }


/* Retype a RAM untyped into a 2 MiB large page mapped at `vaddr`; return its
 * physical address (for DMA), or 0 on failure. */
static u64 alloc_dma_2m(u64 vaddr)
{
    u64 bi = rt_bootinfo;
    u64 start = bi_word(bi, BI_UNTYPED_START);
    u64 slot = find_ram_untyped(21);

    if (slot == (u64)-1) return 0;
    {
        u64 desc = bi + BI_UNTYPED_LIST + (slot - start) * 16;
        u64 paddr = ((volatile u64 *)(desc + 0))[0];
        u64 target = next_slot++;
        mark_untyped_used(slot);
        if (retype_large_page(slot, target) != 0) return 0;
        if (map_page(target, vaddr) != 0) return 0;
        return paddr;
    }
}

/* Ring offsets within a legacy queue (used ring is page-aligned, QueueAlign=4K). */
static u64 vring_avail_off(u16 qnum) { return (u64)qnum * 16; }
static u64 vring_used_off(u16 qnum)
{
    u64 off = (u64)qnum * 16 + (4 + 2 * (u64)qnum);
    return (off + 4095) & ~4095u;
}

/* Configure one virtqueue (split layout) at physical `q_pa`.
 * QEMU's virtio-mmio reports Version=1 (legacy), so this uses QueueAlign +
 * QueuePFN (the descriptor/available/used rings are one contiguous block). */
static void setup_queue(volatile u32 *regs, u32 qidx, u64 q_pa, u16 qnum)
{
    mmio32w(regs, VMMIO_QUEUE_SEL, qidx);
    mmio32w(regs, VMMIO_QUEUE_NUM, qnum);
    mmio32w(regs, VMMIO_QUEUE_ALIGN, 4096);
    mmio32w(regs, VMMIO_QUEUE_PFN, (u32)(q_pa >> 12));  /* PFN = phys / 4096 */
}

/* =============================================================================
 * virtio-net virtqueue driver: honest split-ring management.
 *
 * Replaces the earlier "re-arm descriptor 0" scheme with a proper descriptor
 * ring: an RX buffer pool (one WRITE descriptor per buffer, recycled through
 * the used ring) and rotating TX descriptors.  avail_idx/used_idx advance
 * monotonically; the device's per-entry descriptor id (from the used ring) is
 * what selects the buffer, never a hardcoded descriptor 0.
 *
 * Busy-poll is retained for now -- IRQ routing is a separate follow-up.
 * ============================================================================= */

/* DMA frame layout (single 2 MiB frame mapped at 0x600000):
 *
 *   RX desc/avail    0x0000   (page 0)
 *   RX used          0x1000   (page 1)
 *   RX buffers       0x2000 + d * 0x1000   (4 x 4096, len 1510)
 *   TX desc/avail    0x6000   (page 6)
 *   TX used          0x7000   (page 7)
 *   TX buffers       0x8000 + d * 0x1000   (4 x 4096)
 */
#define RX_BUF_BASE    0x2000
#define RX_BUF_STRIDE  0x1000
#define TX_QUEUE_BASE  0x6000
#define TX_BUF_BASE    0x8000
#define TX_BUF_STRIDE  0x1000
#define NET_BUF_LEN    1510

/* File-scope device/ring state (populated by virtio_net_init). */
static volatile u32 *net_regs;
static volatile u8  *net_dma;
static u64           net_dma_pa;
static volatile struct vring_desc  *net_rx_desc;
static volatile struct vring_avail *net_rx_avail;
static volatile struct vring_used  *net_rx_used;
static volatile struct vring_desc  *net_tx_desc;
static volatile struct vring_avail *net_tx_avail;
static volatile struct vring_used  *net_tx_used;
static u16 net_rx_last_used;   /* used->idx entries consumed so far */
static u16 net_tx_last_used;   /* used->idx entries consumed so far (TX) */
static u16 net_tx_next;        /* rotating TX descriptor id */
static int net_rx_cur;         /* descriptor of the current RX frame (-1 = none) */

static inline void net_barrier(void)
{
    __asm__ volatile("dmb sy" ::: "memory");
}

/* Waiter thread: blocks on the IRQ notification, Acks the IRQ, and wakes the
 * main thread via the "IRQ arrived" notification.  Runs on its own stack
 * (reuses an unused region of the DMA frame). */
#define WAITER_STACK_OFF   0x100000  /* 1 MiB into the 2 MiB DMA frame */
#define WAITER_STACK_SIZE  0x4000    /* 16 KiB */

static void __attribute__((noreturn)) irq_waiter(void)
{
    for (;;) {
        (void)sel4_wait(net_irq_ntfn);
        (void)sel4_irq_handler_ack(net_irq_handler);
        sel4_signal(net_main_ntfn);
    }
}

/* Block until the waiter signals that a virtio IRQ was delivered. */
static u32 irq_poll(void)
{
    (void)sel4_wait(net_main_ntfn);
    net_irq_count++;
    return 1;
}

/* Number of IRQs delivered through the seL4 notification so far. */
u32 virtio_net_irq_count(void)
{
    return net_irq_count;
}

/* Post descriptor `d` to the RX avail ring (device may write into it). */
static void rx_post(u16 d)
{
    net_rx_avail->ring[net_rx_avail->idx % VQ_NUM] = d;
    net_rx_avail->idx = (u16)(net_rx_avail->idx + 1);
    net_barrier();
}

static void rx_kick(void)
{
    mmio32w(net_regs, VMMIO_QUEUE_NOTIFY, 0);
}

/* Return the id of the next used RX descriptor, or -1 if none is pending. */
static int rx_poll(void)
{
    u16 d;
    if (net_rx_used->idx == net_rx_last_used) return -1;
    d = net_rx_used->ring[net_rx_last_used % VQ_NUM].id;
    net_rx_last_used = (u16)(net_rx_last_used + 1);
    return (int)d;
}

/* Pointer to the Ethernet frame of a received descriptor (past the 10-byte
 * virtio_net_hdr). */
static const volatile u8 *rx_frame(int d)
{
    return (const volatile u8 *)(net_dma + RX_BUF_BASE + (u64)d * RX_BUF_STRIDE + 10);
}

/* Block until a frame arrives; return a pointer to the Ethernet frame (past
 * the 10-byte virtio_net_hdr). */
const volatile u8 *virtio_net_rx(void)
{
    int d;
    for (;;) {
        (void)irq_poll();
        d = rx_poll();
        if (d >= 0) {
            net_rx_cur = d;
            return rx_frame(d);
        }
    }
}

/* Recycle the current frame's buffer back to the device. */
void virtio_net_rx_done(void)
{
    rx_post((u16)net_rx_cur);
    rx_kick();
    net_rx_cur = -1;
}

/* Buffer for the next rotating TX descriptor. */
volatile u8 *virtio_net_tx_buffer(void)
{
    return net_dma + TX_BUF_BASE + (u64)net_tx_next * TX_BUF_STRIDE;
}

/* Submit the current TX buffer (len bytes incl. virtio_net_hdr) and wait for
 * the device to consume it. */
void virtio_net_tx_send(u32 len)
{
    u16 d = net_tx_next;

    net_tx_desc[d].addr  = net_dma_pa + TX_BUF_BASE + (u64)d * TX_BUF_STRIDE;
    net_tx_desc[d].len   = len;
    net_tx_desc[d].flags = 0;
    net_tx_desc[d].next  = 0;
    net_tx_avail->ring[net_tx_avail->idx % VQ_NUM] = d;
    net_tx_avail->idx = (u16)(net_tx_avail->idx + 1);
    net_barrier();
    mmio32w(net_regs, VMMIO_QUEUE_NOTIFY, 1);

    while (net_tx_used->idx <= net_tx_last_used)
        (void)irq_poll();
    net_tx_last_used = (u16)(net_tx_last_used + 1);
    net_tx_next = (u16)((d + 1) % VQ_NUM);
}

/* Reset + feature negotiation + queue setup + RX pool + IRQ path.  Returns 1
 * on success. */
int virtio_net_init(void)
{
    u64 dma_pa;
    volatile u8 *dma;
    int i;

    net_regs = get_dev_regs();
    if (net_regs == 0 || net_regs[0] != 0x74726976u) return 0;

    /* Reset + ACKNOWLEDGE + DRIVER + FEATURES_OK. */
    mmio32w(net_regs, VMMIO_STATUS, 0);
    mmio32w(net_regs, VMMIO_STATUS, VIRTIO_STATUS_ACKNOWLEDGE);
    mmio32w(net_regs, VMMIO_STATUS, VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER);
    mmio32w(net_regs, 0x024, 0);                 /* DriverFeaturesSel = page 0 */
    mmio32w(net_regs, VMMIO_DRIVER_FEATURES, 1u << 5);  /* accept VIRTIO_NET_F_MAC */
    mmio32w(net_regs, VMMIO_STATUS,
            VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER | VIRTIO_STATUS_FEATURES_OK);
    mmio32w(net_regs, 0x028, 4096);   /* GuestPageSize (legacy) */

    /* Allocate a 2 MiB DMA frame. */
    dma_pa = alloc_dma_2m(0x600000ULL);
    if (dma_pa == 0) return 0;
    dma = (volatile u8 *)0x600000ULL;
    net_dma = dma;
    net_dma_pa = dma_pa;

    /* Set up the virtio IRQ -> seL4 Notification path. */
    {
        u64 ntfn_slot = next_slot++;
        u64 badged_slot = next_slot++;
        u64 irq_handler_slot = next_slot++;
        u64 ram = find_ram_untyped(5);
        if (ram == (u64)-1) return 0;
        mark_untyped_used(ram);
        if (retype_notification(ram, ntfn_slot) != 0) return 0;
        if (sel4_cnode_mint(2 /* root CNode */, badged_slot, ROOT_CNODE_DEPTH,
                            2 /* root CNode */, ntfn_slot, ROOT_CNODE_DEPTH,
                            3 /* ReadWrite */, VIRTIO_MMIO_IRQ) != 0) return 0;
        if (sel4_irq_control_get(4 /* seL4_CapIRQControl */, VIRTIO_MMIO_IRQ, irq_handler_slot, ROOT_CNODE_DEPTH) != 0) return 0;
        if (sel4_irq_handler_set_ntfn(irq_handler_slot, badged_slot) != 0) return 0;
        net_irq_ntfn = badged_slot;
        net_irq_handler = irq_handler_slot;
    }

    /* Second notification: the waiter signals it to wake the main thread. */
    {
        u64 main_ntfn_slot = next_slot++;
        u64 ram = find_ram_untyped(5);
        if (ram == (u64)-1) return 0;
        mark_untyped_used(ram);
        if (retype_notification(ram, main_ntfn_slot) != 0) return 0;
        net_main_ntfn = main_ntfn_slot;
    }

    /* Waiter thread: blocks on the IRQ notification and forwards IRQs. */
    {
        u64 tcb_slot = next_slot++;
        u64 ram = find_ram_untyped(11);
        if (ram == (u64)-1) return 0;
        mark_untyped_used(ram);
        if (retype_tcb(ram, tcb_slot) != 0) return 0;
        if (sel4_tcb_configure(tcb_slot, 0 /* fault_ep */, 2 /* cspace_root */, 0,
                              3 /* vspace_root */, 0, 0 /* buffer */, 0 /* bufferFrame */) != 0) return 0;
        if (sel4_tcb_write_registers(tcb_slot, (u64)irq_waiter,
                                     (u64)net_dma + WAITER_STACK_OFF + WAITER_STACK_SIZE) != 0) return 0;
    }

    /* RX queue (index 0) at DMA offset 0. */
    setup_queue(net_regs, 0, dma_pa, VQ_NUM);
    net_rx_desc  = (volatile struct vring_desc *)(dma + 0);
    net_rx_avail = (volatile struct vring_avail *)(dma + vring_avail_off(VQ_NUM));
    net_rx_used  = (volatile struct vring_used *)(dma + vring_used_off(VQ_NUM));

    /* TX queue (index 1) at DMA offset TX_QUEUE_BASE. */
    setup_queue(net_regs, 1, dma_pa + TX_QUEUE_BASE, VQ_NUM);
    net_tx_desc  = (volatile struct vring_desc *)(dma + TX_QUEUE_BASE);
    net_tx_avail = (volatile struct vring_avail *)(dma + TX_QUEUE_BASE + vring_avail_off(VQ_NUM));
    net_tx_used  = (volatile struct vring_used *)(dma + TX_QUEUE_BASE + vring_used_off(VQ_NUM));

    /* Fresh ring headers (the DMA frame is not pre-zeroed). */
    net_rx_avail->flags = 0;
    net_rx_avail->idx   = 0;
    net_rx_used->flags  = 0;
    net_rx_used->idx    = 0;
    net_tx_avail->flags = 0;
    net_tx_avail->idx   = 0;
    net_tx_used->flags  = 0;
    net_tx_used->idx    = 0;

    /* RX pool: one WRITE descriptor per buffer, all posted up front. */
    for (i = 0; i < VQ_NUM; i++) {
        net_rx_desc[i].addr  = dma_pa + RX_BUF_BASE + (u64)i * RX_BUF_STRIDE;
        net_rx_desc[i].len   = NET_BUF_LEN;
        net_rx_desc[i].flags = 2;   /* WRITE */
        net_rx_desc[i].next  = 0;
        rx_post((u16)i);
    }
    rx_kick();

    net_rx_last_used = 0;
    net_tx_last_used = 0;
    net_tx_next      = 0;

    /* DRIVER_OK. */
    mmio32w(net_regs, VMMIO_STATUS,
            VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER |
            VIRTIO_STATUS_FEATURES_OK | VIRTIO_STATUS_DRIVER_OK);

    return 1;
}

/* =============================================================================
 * Child-domain spawn (isolation demo, increment 1).
 *
 * Creates a child TCB with its OWN CSpace (a fresh 8-slot CNode) that contains
 * only a badged result notification, sharing the root VSpace.  The child runs
 * `schild_child_main`, signals its slot 0, and halts; the root waits on its
 * copy of the result notification and observes the badge.
 * ============================================================================= */

#define CHILD_CNODE_RADIX 3     /* 2^3 = 8 slots */
#define CHILD_BADGE       42
#define CHILD_STACK_VA    0x800000   /* free 2 MiB-aligned VA (past the DMA frame) */
#define CHILD_STACK_SIZE  0x4000     /* 16 KiB stack (within the 2 MiB page) */

static u64 child_result_ntfn;   /* root's cap to the child's result notification */

static void __attribute__((noreturn)) schild_child_main(void)
{
    /* Child CSpace slot 0 = badged result notification. */
    sel4_signal(0);
    for (;;) { }
}

/* Spawn the child.  Returns 1 on success. */
int schild_spawn_child(void)
{
    u64 cnode_slot = next_slot++;
    u64 ntfn_slot  = next_slot++;
    u64 tcb_slot   = next_slot++;
    u64 stack_slot = next_slot++;
    u64 ram;

    /* Child CNode (8 slots). */
    ram = find_ram_untyped(8);
    if (ram == (u64)-1) return 0;
    mark_untyped_used(ram);
    if (retype_cnode(ram, cnode_slot, CHILD_CNODE_RADIX) != 0) return 0;

    /* Result notification. */
    ram = find_ram_untyped(5);
    if (ram == (u64)-1) return 0;
    mark_untyped_used(ram);
    if (retype_notification(ram, ntfn_slot) != 0) return 0;

    /* Mint the result notification into the child's slot 0, badged. */
    if (sel4_cnode_mint(cnode_slot, 0, CHILD_CNODE_RADIX,
                        2 /* root CNode */, ntfn_slot, ROOT_CNODE_DEPTH,
                        3 /* ReadWrite */, CHILD_BADGE) != 0) return 0;

    /* Child stack: a 2 MiB large page at CHILD_STACK_VA (block mapping, so no
     * intermediate page table is required -- unlike a 4 KiB small page). */
    ram = find_ram_untyped(21);
    if (ram == (u64)-1) return 0;
    mark_untyped_used(ram);
    if (retype_large_page(ram, stack_slot) != 0) return 0;
    if (map_page(stack_slot, CHILD_STACK_VA) != 0) return 0;

    /* Child TCB. */
    ram = find_ram_untyped(11);
    if (ram == (u64)-1) return 0;
    mark_untyped_used(ram);
    if (retype_tcb(ram, tcb_slot) != 0) return 0;

    /* Configure: own CSpace (child CNode), shared VSpace, no IPC buffer. */
    if (sel4_tcb_configure(tcb_slot, 0 /* fault_ep */, cnode_slot, 0,
                           3 /* vspace_root */, 0, 0 /* buffer */, 0 /* bufferFrame */) != 0) return 0;
    if (sel4_tcb_write_registers(tcb_slot, (u64)schild_child_main,
                                 CHILD_STACK_VA + CHILD_STACK_SIZE) != 0) return 0;

    child_result_ntfn = ntfn_slot;
    return 1;
}

/* Wait for the child's result signal; return the badge. */
u64 schild_child_wait(void)
{
    return sel4_wait(child_result_ntfn);
}

