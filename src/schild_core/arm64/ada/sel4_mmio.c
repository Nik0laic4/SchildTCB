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
static u64 dev_page_cap;     /* device MMIO large-page cap (root CNode slot) */
static u64 dma_page_cap;     /* DMA large-page cap (root CNode slot) */

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

/* Retype `num` objects of `type`/`size_bits` from `untyped`, placing the cap(s)
 * at `target_slot` of `cnode`. */
static u64 retype_object(u64 untyped, u64 cnode, u64 target_slot, u64 type, u64 size_bits)
{
    u64 info = (1ULL << 12) | (1ULL << 7) | 6ULL;  /* UntypedRetype: label=1, extraCaps=1, len=6 */
    set_cap(0, cnode);
    set_mr(4, target_slot);
    set_mr(5, 1);
    return info_label(sel4_call(untyped, info, type, size_bits, 0, 0));
}

/* Map a page into `vspace` at `vaddr`. */
static u64 map_page_ctx(u64 page_cap, u64 vaddr, u64 vspace)
{
    u64 info = (40ULL << 12) | (1ULL << 7) | 3ULL; /* ARMPageMap: label=40, extraCaps=1, len=3 */
    set_cap(0, vspace);
    return info_label(sel4_call(page_cap, info, vaddr, 3, 0, 0));
}

/* CSpace context for the IRQ path (populated per domain). */
struct irq_ctx {
    u64 cnode;        /* CNode cap (retype/mint + waiter cspace_root) */
    u64 cnode_depth;  /* depth to address a slot in cnode */
    u64 vspace;       /* VSpace cap (waiter vspace_root) */
    u64 ram;          /* RAM untyped cap */
    u64 irq_handler;  /* IRQ handler cap */
    u64 slot_base;    /* first retype target slot in cnode */
};

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
            dev_page_cap = target;
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
        dma_page_cap = target;
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

/* Bring up the device: reset, features, DMA frame, queues, RX pool, DRIVER_OK.
 * Sets net_regs/net_dma/net_dma_pa + ring state.  Returns 1 on success. */
int virtio_net_init_device(void)
{
    u64 dma_pa;
    volatile u8 *dma;
    int i;

    net_regs = get_dev_regs();
    if (net_regs == 0 || net_regs[0] != 0x74726976u) return 0;

    mmio32w(net_regs, VMMIO_STATUS, 0);
    mmio32w(net_regs, VMMIO_STATUS, VIRTIO_STATUS_ACKNOWLEDGE);
    mmio32w(net_regs, VMMIO_STATUS, VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER);
    mmio32w(net_regs, 0x024, 0);
    mmio32w(net_regs, VMMIO_DRIVER_FEATURES, 1u << 5);
    mmio32w(net_regs, VMMIO_STATUS,
            VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER | VIRTIO_STATUS_FEATURES_OK);
    mmio32w(net_regs, 0x028, 4096);

    dma_pa = alloc_dma_2m(0x600000ULL);
    if (dma_pa == 0) return 0;
    dma = (volatile u8 *)0x600000ULL;
    net_dma = dma;
    net_dma_pa = dma_pa;

    setup_queue(net_regs, 0, dma_pa, VQ_NUM);
    net_rx_desc  = (volatile struct vring_desc *)(dma + 0);
    net_rx_avail = (volatile struct vring_avail *)(dma + vring_avail_off(VQ_NUM));
    net_rx_used  = (volatile struct vring_used *)(dma + vring_used_off(VQ_NUM));

    setup_queue(net_regs, 1, dma_pa + TX_QUEUE_BASE, VQ_NUM);
    net_tx_desc  = (volatile struct vring_desc *)(dma + TX_QUEUE_BASE);
    net_tx_avail = (volatile struct vring_avail *)(dma + TX_QUEUE_BASE + vring_avail_off(VQ_NUM));
    net_tx_used  = (volatile struct vring_used *)(dma + TX_QUEUE_BASE + vring_used_off(VQ_NUM));

    net_rx_avail->flags = 0;
    net_rx_avail->idx   = 0;
    net_rx_used->flags  = 0;
    net_rx_used->idx    = 0;
    net_tx_avail->flags = 0;
    net_tx_avail->idx   = 0;
    net_tx_used->flags  = 0;
    net_tx_used->idx    = 0;

    for (i = 0; i < VQ_NUM; i++) {
        net_rx_desc[i].addr  = dma_pa + RX_BUF_BASE + (u64)i * RX_BUF_STRIDE;
        net_rx_desc[i].len   = NET_BUF_LEN;
        net_rx_desc[i].flags = 2;
        net_rx_desc[i].next  = 0;
        rx_post((u16)i);
    }
    rx_kick();

    net_rx_last_used = 0;
    net_tx_last_used = 0;
    net_tx_next      = 0;

    mmio32w(net_regs, VMMIO_STATUS,
            VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER |
            VIRTIO_STATUS_FEATURES_OK | VIRTIO_STATUS_DRIVER_OK);

    return 1;
}

/* Set up the IRQ path (notification + waiter TCB) in the given CSpace context.
 * Retypes notification x2 + TCB from `c->ram`.  Returns 1 on success. */
static int virtio_net_init_irq(const struct irq_ctx *c)
{
    u64 ntfn_slot      = c->slot_base;
    u64 badged_slot    = c->slot_base + 1;
    u64 main_ntfn_slot = c->slot_base + 2;
    u64 tcb_slot       = c->slot_base + 3;

    if (retype_object(c->ram, c->cnode, ntfn_slot, 3 /* NotificationObject */, 5) != 0) return 0;
    if (sel4_cnode_mint(c->cnode, badged_slot, c->cnode_depth,
                        c->cnode, ntfn_slot, c->cnode_depth,
                        3 /* ReadWrite */, VIRTIO_MMIO_IRQ) != 0) return 0;
    if (sel4_irq_handler_set_ntfn(c->irq_handler, badged_slot) != 0) return 0;
    net_irq_ntfn = badged_slot;
    net_irq_handler = c->irq_handler;

    if (retype_object(c->ram, c->cnode, main_ntfn_slot, 3, 5) != 0) return 0;
    net_main_ntfn = main_ntfn_slot;

    if (retype_object(c->ram, c->cnode, tcb_slot, 1 /* TCBObject */, 11) != 0) return 0;
    if (sel4_tcb_configure(tcb_slot, 0 /* fault_ep */, c->cnode, 0,
                           c->vspace, 0, 0 /* buffer */, 0 /* bufferFrame */) != 0) return 0;
    if (sel4_tcb_write_registers(tcb_slot, (u64)irq_waiter,
                                 (u64)net_dma + WAITER_STACK_OFF + WAITER_STACK_SIZE) != 0) return 0;

    return 1;
}

/* Full init (device + IRQ) in the root task's CSpace. */
int virtio_net_init(void)
{
    u64 ram;
    u64 irq_handler_slot;
    struct irq_ctx ctx;

    if (!virtio_net_init_device()) return 0;

    ram = find_ram_untyped(12);   /* >= 4 KiB: notification x2 + TCB */
    if (ram == (u64)-1) return 0;
    mark_untyped_used(ram);

    irq_handler_slot = next_slot++;
    if (sel4_irq_control_get(4 /* seL4_CapIRQControl */, VIRTIO_MMIO_IRQ,
                             irq_handler_slot, ROOT_CNODE_DEPTH) != 0) return 0;

    ctx.cnode = 2;
    ctx.cnode_depth = ROOT_CNODE_DEPTH;
    ctx.vspace = 3;
    ctx.ram = ram;
    ctx.irq_handler = irq_handler_slot;
    ctx.slot_base = next_slot;
    if (!virtio_net_init_irq(&ctx)) return 0;
    next_slot = ctx.slot_base + 4;

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

/* =============================================================================
 * Net child: a child TCB with its own CSpace runs the driver IRQ path + the
 * protocol test, sharing the device (MMIO/DMA/queues) already initialized by
 * the root via virtio_net_init_device().
 *
 * Child CSpace (16 slots, radix 4):
 *   0 = self CNode cap, 1 = RAM untyped, 2 = IRQ handler, 3 = VSpace,
 *   4 = result notification (badge 42), 5..8 = IRQ-path retype targets.
 * ============================================================================= */

#define NET_CHILD_CNODE_RADIX 4   /* 16 slots */
#define CHILD_IPC_BUF_VA     0x900000  /* child IPC buffer (within stack page) */

extern u64 schild_virtio_net_run_test(void);

static u64 child_test_result;

static void __attribute__((noreturn)) schild_net_child_main(void)
{
    struct irq_ctx ctx;
    u64 result = 0;

    /* The child's syscalls use its own IPC buffer (not the root's). */
    ipc_buf = CHILD_IPC_BUF_VA;

    ctx.cnode = 0;       /* self CNode */
    ctx.cnode_depth = NET_CHILD_CNODE_RADIX;
    ctx.vspace = 3;      /* VSpace */
    ctx.ram = 1;         /* RAM untyped */
    ctx.irq_handler = 2; /* IRQ handler */
    ctx.slot_base = 5;   /* IRQ ntfn(5), badged(6), main ntfn(7), TCB(8) */

    if (virtio_net_init_irq(&ctx))
        result = schild_virtio_net_run_test();

    child_test_result = result;
    sel4_signal(4);   /* result notification */
    for (;;) { }
}

int schild_spawn_net_child(void)
{
    u64 cnode_slot = next_slot++;
    u64 irq_handler_slot = next_slot++;
    u64 ntfn_slot = next_slot++;
    u64 stack_slot = next_slot++;
    u64 tcb_slot = next_slot++;
    u64 ram;

    /* Child CNode (16 slots). */
    ram = find_ram_untyped(8);
    if (ram == (u64)-1) return 0;
    mark_untyped_used(ram);
    if (retype_cnode(ram, cnode_slot, NET_CHILD_CNODE_RADIX) != 0) return 0;

    /* Mint the child CNode into its own slot 0 (self CNode cap). */
    if (sel4_cnode_mint(cnode_slot, 0, NET_CHILD_CNODE_RADIX,
                        2, cnode_slot, ROOT_CNODE_DEPTH, 3, 0) != 0) return 0;

    /* RAM untyped -> child slot 1 (for the child's IRQ objects). */
    ram = find_ram_untyped(12);
    if (ram == (u64)-1) return 0;
    mark_untyped_used(ram);
    if (sel4_cnode_mint(cnode_slot, 1, NET_CHILD_CNODE_RADIX,
                        2, ram, ROOT_CNODE_DEPTH, 3, 0) != 0) return 0;

    /* IRQ handler -> child slot 2. */
    if (sel4_irq_control_get(4, VIRTIO_MMIO_IRQ, irq_handler_slot, ROOT_CNODE_DEPTH) != 0) return 0;
    if (sel4_cnode_mint(cnode_slot, 2, NET_CHILD_CNODE_RADIX,
                        2, irq_handler_slot, ROOT_CNODE_DEPTH, 3, 0) != 0) return 0;

    /* VSpace -> child slot 3. */
    if (sel4_cnode_mint(cnode_slot, 3, NET_CHILD_CNODE_RADIX,
                        2, 3, ROOT_CNODE_DEPTH, 3, 0) != 0) return 0;

    /* Result notification -> child slot 4 (badge 42). */
    ram = find_ram_untyped(5);
    if (ram == (u64)-1) return 0;
    mark_untyped_used(ram);
    if (retype_notification(ram, ntfn_slot) != 0) return 0;
    if (sel4_cnode_mint(cnode_slot, 4, NET_CHILD_CNODE_RADIX,
                        2, ntfn_slot, ROOT_CNODE_DEPTH, 3, CHILD_BADGE) != 0) return 0;
    child_result_ntfn = ntfn_slot;

    /* Child stack: a 2 MiB large page at CHILD_STACK_VA (block mapping). */
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
    if (sel4_tcb_configure(tcb_slot, 0, cnode_slot, 0, 3, 0,
                           CHILD_IPC_BUF_VA /* buffer */, stack_slot /* bufferFrame */) != 0) return 0;
    if (sel4_tcb_write_registers(tcb_slot, (u64)schild_net_child_main,
                                 CHILD_STACK_VA + CHILD_STACK_SIZE) != 0) return 0;

    return 1;
}

/* Root side: init the device, spawn the net child, wait for its result. */
u64 schild_net_child_test(void)
{
    if (!virtio_net_init_device()) return 0;
    if (!schild_spawn_net_child()) return 0;
    (void)schild_child_wait();
    return child_test_result;
}

/* =============================================================================
 * ELF process spawn (increment: separate VSpace + child ELF).
 *
 * The root task creates a *separate* VSpace for a child process, loads a
 * self-contained child ELF into it (code RX / data RW+NX, both cacheable) and
 * runs it with its own CSpace.  The child proves it runs in its own address
 * space by printing over the debug console and signalling a badged result
 * notification; the root observes badge ELF_CHILD_BADGE.
 *
 * AArch64 user translation has 4 levels (48-bit VA): the VSpaceObject is the
 * root (512 slots), then three PageTableObjects (L2/L1/L0) before a 4 KiB
 * small page.  A fresh VSpace needs an ASID from an ASID pool before any page
 * can be mapped; the pool is created from a 4 KiB untyped via
 * ARMASIDControlMakePool, and the VSpace is bound via ARMASIDPoolAssign.
 * ============================================================================= */

/* ---- seL4 AArch64 object types (non-MCS, from libsel4 objecttype.h) ---- */
#define OBJ_UNTYPED       0
#define OBJ_TCB           1
#define OBJ_NOTIFICATION  3
#define OBJ_CAPTABLE      4
#define OBJ_VSPACE        6
#define OBJ_SMALL_PAGE    7
#define OBJ_LARGE_PAGE    8
#define OBJ_PAGE_TABLE    9

/* ---- seL4 AArch64 invocation labels (non-MCS) ---- */
#define LBL_PAGE_TABLE_MAP  38
#define LBL_PAGE_MAP        40
#define LBL_PAGE_UNMAP      41
#define LBL_ASID_MAKE_POOL  47
#define LBL_ASID_ASSIGN     48

/* ---- fixed root-CNode capabilities ---- */
#define CAP_ROOT_CNODE   2
#define CAP_ROOT_VSPACE  3
#define CAP_ASID_CONTROL 5

/* ---- capability rights / VM attributes for ARMPageMap ---- */
/* seL4_CapRights: bit0=Write, bit1=Read (seL4_CanRead = 1<<1 = 2). */
#define RIGHTS_READ            2
#define RIGHTS_RW              3
#define ATTR_CACHEABLE         0x01   /* seL4_ARM_PageCacheable */
#define ATTR_EXECUTE_NEVER     0x04   /* seL4_ARM_ExecuteNever  */

/* Child ELF is linked at 0x400000 (separate VSpace, so no root conflict). */
#define CHILD_ELF_VA   0x400000
/* Free VA in the root VSpace used as a scratch slot while filling frames. */
#define COPY_VA        0xA00000
#define ELF_CHILD_BADGE 42

/* Embedded child ELF image (obj_child/child.elf, emitted by build_root.sh). */
extern const u8 child_elf_start[];
extern const u8 child_elf_end[];

/* ---- ELF64 structures (freestanding; no <elf.h>) ---- */
struct elf64_ehdr {
    unsigned char e_ident[16];
    u16 e_type, e_machine;
    u32 e_version;
    u64 e_entry, e_phoff, e_shoff;
    u32 e_flags;
    u16 e_ehsize, e_phentsize, e_phnum, e_shentsize, e_shnum, e_shstrndx;
};

struct elf64_phdr {
    u32 p_type, p_flags;
    u64 p_offset, p_vaddr, p_paddr, p_filesz, p_memsz, p_align;
};

/* Map a page table into `vspace` at `vaddr` (ARMPageTableMap).  The kernel
 * installs it at the level the page-table walk stops at. */
static u64 map_page_table(u64 pt_cap, u64 vspace, u64 vaddr)
{
    u64 info = (LBL_PAGE_TABLE_MAP << 12) | (1ULL << 7) | 2ULL;
    set_cap(0, vspace);
    return info_label(sel4_call(pt_cap, info, vaddr, 0 /* attr ignored */, 0, 0));
}

/* Map a frame into `vspace` at `vaddr` with `rights` and `attr`. */
static u64 map_frame(u64 page_cap, u64 vspace, u64 vaddr, u64 rights, u64 attr)
{
    u64 info = (LBL_PAGE_MAP << 12) | (1ULL << 7) | 3ULL;
    set_cap(0, vspace);
    return info_label(sel4_call(page_cap, info, vaddr, rights, attr, 0));
}

/* Unmap a frame from whatever VSpace it is mapped in (ARMPageUnmap). */
static u64 unmap_frame(u64 page_cap)
{
    u64 info = (LBL_PAGE_UNMAP << 12) | 0ULL;
    return info_label(sel4_call(page_cap, info, 0, 0, 0, 0));
}

/* Create a fresh VSpace: retype a VSpaceObject, carve a 4 KiB untyped, create
 * an ASID pool from it (ARMASIDControlMakePool) and assign the VSpace an ASID
 * (ARMASIDPoolAssign).  Returns the VSpace CPtr (a root-CNode slot) or 0. */
static u64 vspace_new(void)
{
    u64 vspace_slot       = next_slot++;
    u64 asid_pool_slot    = next_slot++;
    u64 pool_untyped_slot = next_slot++;
    u64 ram;
    u64 info;
    u64 err;

    ram = find_ram_untyped(12 /* seL4_VSpaceBits */);
    if (ram == (u64)-1) return 0;
    mark_untyped_used(ram);
    if (retype_object(ram, CAP_ROOT_CNODE, vspace_slot, OBJ_VSPACE, 12) != 0) return 0;

    ram = find_ram_untyped(12 /* seL4_ASIDPoolBits */);
    if (ram == (u64)-1) return 0;
    mark_untyped_used(ram);
    if (retype_object(ram, CAP_ROOT_CNODE, pool_untyped_slot, OBJ_UNTYPED, 12) != 0) return 0;

    /* ARMASIDControlMakePool: EC[0]=untyped, EC[1]=root CNode. */
    info = (LBL_ASID_MAKE_POOL << 12) | (2ULL << 7) | 2ULL;
    set_cap(0, pool_untyped_slot);
    set_cap(1, CAP_ROOT_CNODE);
    err = info_label(sel4_call(CAP_ASID_CONTROL, info, asid_pool_slot,
                               ROOT_CNODE_DEPTH, 0, 0));
    if (err != 0) return 0;

    /* ARMASIDPoolAssign: EC[0]=vspace. */
    info = (LBL_ASID_ASSIGN << 12) | (1ULL << 7) | 0ULL;
    set_cap(0, vspace_slot);
    err = info_label(sel4_call(asid_pool_slot, info, 0, 0, 0, 0));
    if (err != 0) return 0;

    return vspace_slot;
}

/* Load one PT_LOAD segment into the child VSpace: retype a 4 KiB frame per
 * page, fill it via a temporary root-VSpace mapping (COPY_VA), then map it at
 * its final VA with the right permissions (PF_X -> RX, else RW+NX). */
static u64 elf_load_segment(u64 vspace, u64 seg_untyped, const u8 *img,
                            const struct elf64_phdr *ph)
{
    u64 vstart = ph->p_vaddr & ~0xfffULL;
    u64 vend   = (ph->p_vaddr + ph->p_memsz + 0xfffULL) & ~0xfffULL;
    u64 rights = (ph->p_flags & 1 /* PF_X */) ? RIGHTS_READ : RIGHTS_RW;
    u64 attr   = (ph->p_flags & 1 /* PF_X */) ? ATTR_CACHEABLE
                                              : (ATTR_CACHEABLE | ATTR_EXECUTE_NEVER);
    u64 va;

    for (va = vstart; va < vend; va += 0x1000) {
        u64 frame_slot = next_slot++;
        u64 off_in_seg = va - ph->p_vaddr;
        u64 copy_len = 0;
        u64 i;

        if (retype_object(seg_untyped, CAP_ROOT_CNODE, frame_slot,
                          OBJ_SMALL_PAGE, 12) != 0)
            return 0;

        if (map_frame(frame_slot, CAP_ROOT_VSPACE, COPY_VA, RIGHTS_RW, ATTR_CACHEABLE) != 0)
            return 0;

        if (off_in_seg < ph->p_filesz) {
            copy_len = ph->p_filesz - off_in_seg;
            if (copy_len > 0x1000) copy_len = 0x1000;
        }
        for (i = 0; i < copy_len; i++)
            ((volatile u8 *)COPY_VA)[i] = img[ph->p_offset + off_in_seg + i];
        for (; i < 0x1000; i++)
            ((volatile u8 *)COPY_VA)[i] = 0;

        if (unmap_frame(frame_slot) != 0) return 0;
        if (map_frame(frame_slot, vspace, va, rights, attr) != 0) return 0;
    }
    return 1;
}

/* Full ELF-child test: create a VSpace, load the embedded child ELF, spawn a
 * TCB with its own CSpace + VSpace, and wait for the child's signal.  Returns
 * the child's badge (ELF_CHILD_BADGE) on success, 0 on failure. */
u64 schild_elf_child_test(void)
{
    const struct elf64_ehdr *eh = (const struct elf64_ehdr *)child_elf_start;
    u64 vspace_slot, cnode_slot, ntfn_slot, tcb_slot;
    u64 pt_untyped, seg_untyped;
    u64 l2_slot, l1_slot, l0_slot, root_l0_slot;
    u64 ram;
    u64 entry;
    int i;

    /* The net child (same ELF, shared data) switched ipc_buf to its own
     * CHILD_IPC_BUF_VA; restore the root's IPC buffer before any root syscall. */
    ipc_buf = bi_word(rt_bootinfo, BI_IPCBUF);

    /* Validate the embedded ELF image. */
    if (eh->e_ident[0] != 0x7f || eh->e_ident[1] != 'E' ||
        eh->e_ident[2] != 'L' || eh->e_ident[3] != 'F' ||
        eh->e_ident[4] != 2 /* ELFCLASS64 */ ||
        eh->e_ident[5] != 1 /* ELFDATA2LSB */ ||
        eh->e_type != 2 /* ET_EXEC */ || eh->e_machine != 183 /* EM_AARCH64 */)
        return 0;

    /* 1. Child VSpace (root page table + ASID). */
    vspace_slot = vspace_new();
    if (vspace_slot == 0) return 0;

    /* 2. Page tables: three for the child's code region (L2/L1/L0) plus one L0
     *    leaf in the ROOT VSpace for the copy scratch.  All four are 4 KiB and
     *    retyped back-to-back from a single untyped. */
    pt_untyped = find_ram_untyped(14 /* 4 x 4 KiB */);
    if (pt_untyped == (u64)-1) return 0;
    mark_untyped_used(pt_untyped);

    l2_slot      = next_slot++;
    l1_slot      = next_slot++;
    l0_slot      = next_slot++;
    root_l0_slot = next_slot++;

    if (retype_object(pt_untyped, CAP_ROOT_CNODE, l2_slot, OBJ_PAGE_TABLE, 12) != 0) return 0;
    if (retype_object(pt_untyped, CAP_ROOT_CNODE, l1_slot, OBJ_PAGE_TABLE, 12) != 0) return 0;
    if (retype_object(pt_untyped, CAP_ROOT_CNODE, l0_slot, OBJ_PAGE_TABLE, 12) != 0) return 0;
    if (retype_object(pt_untyped, CAP_ROOT_CNODE, root_l0_slot, OBJ_PAGE_TABLE, 12) != 0) return 0;

    /* Child VSpace: root -> L2 -> L1 -> L0 leaf for the 2 MiB code region. */
    if (map_page_table(l2_slot, vspace_slot, CHILD_ELF_VA) != 0) return 0;
    if (map_page_table(l1_slot, vspace_slot, CHILD_ELF_VA) != 0) return 0;
    if (map_page_table(l0_slot, vspace_slot, CHILD_ELF_VA) != 0) return 0;

    /* Root VSpace: an L0 leaf at COPY_VA (its L2/L1 already exist from boot). */
    if (map_page_table(root_l0_slot, CAP_ROOT_VSPACE, COPY_VA) != 0) return 0;

    /* 3. Load the child ELF's PT_LOAD segments into the child VSpace. */
    seg_untyped = find_ram_untyped(15 /* >= 32 KiB: 5 pages for the tiny child */);
    if (seg_untyped == (u64)-1) return 0;
    mark_untyped_used(seg_untyped);

    entry = eh->e_entry;
    for (i = 0; i < eh->e_phnum; i++) {
        const struct elf64_phdr *ph = (const struct elf64_phdr *)
            (child_elf_start + eh->e_phoff + (u64)i * eh->e_phentsize);
        if (ph->p_type != 1 /* PT_LOAD */) continue;
        if (!elf_load_segment(vspace_slot, seg_untyped, child_elf_start, ph)) return 0;
    }

    /* 4. Child CSpace: 16-slot CNode with a badged result notification at 0. */
    cnode_slot = next_slot++;
    ntfn_slot  = next_slot++;
    tcb_slot   = next_slot++;

    ram = find_ram_untyped(9 /* radix 4 CNode = 2^(4+5) = 512 B */);
    if (ram == (u64)-1) return 0;
    mark_untyped_used(ram);
    if (retype_cnode(ram, cnode_slot, 4 /* radix: 16 slots */) != 0) return 0;

    ram = find_ram_untyped(5);
    if (ram == (u64)-1) return 0;
    mark_untyped_used(ram);
    if (retype_notification(ram, ntfn_slot) != 0) return 0;

    if (sel4_cnode_mint(cnode_slot, 0, 4,
                        CAP_ROOT_CNODE, ntfn_slot, ROOT_CNODE_DEPTH,
                        3 /* ReadWrite */, ELF_CHILD_BADGE) != 0) return 0;

    /* 5. Child TCB: own CSpace + own VSpace, entry = ELF entry point. */
    ram = find_ram_untyped(11);
    if (ram == (u64)-1) return 0;
    mark_untyped_used(ram);
    if (retype_tcb(ram, tcb_slot) != 0) return 0;

    if (sel4_tcb_configure(tcb_slot, 0 /* fault_ep */, cnode_slot, 0,
                           vspace_slot, 0, 0 /* buffer */, 0 /* bufferFrame */) != 0)
        return 0;
    if (sel4_tcb_write_registers(tcb_slot, entry, 0 /* sp set by child entry */) != 0)
        return 0;

    /* 6. Wait for the child's signal and return its badge. */
    return sel4_wait(ntfn_slot);
}

/* =============================================================================
 * Net child as a real process (separate VSpace + ELF).
 *
 * The root brings the device up (MMIO/DMA/queues/DRIVER_OK) in its OWN VSpace,
 * then hands the device + DMA frame to a child process that runs in a separate
 * VSpace.  The child ELF is built from the same driver + protocol sources, so
 * the child re-attaches to the already-initialised device from a fixed layout
 * and runs the protocol stack end-to-end.
 *
 * Handoff layout (fixed; mirrored by the root and the child entry):
 *   device MMIO  0x200000 (large page, uncached)   -> registers at 0x203e00
 *   DMA frame    0x600000 (large page, uncached)
 *   child IPC    0x900000 (4 KiB, cacheable)
 *   child CSpace: 0=self CNode, 1=RAM untyped, 2=IRQ handler, 3=VSpace,
 *                 4=result ntfn (badge 42), 5..8=IRQ retype targets.
 * ============================================================================= */

/* Child-side entry: run in the child's own VSpace + CSpace.  The root already
 * brought the device up and mapped device + DMA + IPC into this VSpace; we only
 * re-attach the driver state, set up the IRQ path, run the protocol and signal
 * the result. */
void schild_net_elf_child_main(void)
{
    struct irq_ctx ctx;
    u64 result = 0;

    ipc_buf = CHILD_IPC_BUF_VA;

    net_regs = (volatile u32 *)0x203e00;
    net_dma  = (volatile u8  *)0x600000;

    net_rx_desc  = (volatile struct vring_desc *)(net_dma + 0);
    net_rx_avail = (volatile struct vring_avail *)(net_dma + vring_avail_off(VQ_NUM));
    net_rx_used  = (volatile struct vring_used *)(net_dma + vring_used_off(VQ_NUM));
    net_tx_desc  = (volatile struct vring_desc *)(net_dma + TX_QUEUE_BASE);
    net_tx_avail = (volatile struct vring_avail *)(net_dma + TX_QUEUE_BASE + vring_avail_off(VQ_NUM));
    net_tx_used  = (volatile struct vring_used *)(net_dma + TX_QUEUE_BASE + vring_used_off(VQ_NUM));

    /* The DMA physical base was written into RX descriptor 0 by the root. */
    net_dma_pa = net_rx_desc[0].addr - RX_BUF_BASE;

    net_rx_last_used = 0;
    net_tx_last_used = 0;
    net_tx_next      = 0;
    net_rx_cur       = -1;

    ctx.cnode       = 0;
    ctx.cnode_depth = NET_CHILD_CNODE_RADIX;
    ctx.vspace      = 3;
    ctx.ram         = 1;
    ctx.irq_handler = 2;
    ctx.slot_base   = 5;

    if (virtio_net_init_irq(&ctx))
        result = schild_virtio_net_run_test();

    (void)result;
    sel4_signal(4);   /* result notification */
    for (;;) { }
}

/* Root-side: bring the device up in the root VSpace, then hand device + DMA to
 * a child process in its own VSpace, load the child ELF, grant the CSpace caps
 * and wait for the child's result.  Returns the child's badge (42) on success,
 * 0 on failure. */
u64 schild_net_elf_child_test(void)
{
    const struct elf64_ehdr *eh = (const struct elf64_ehdr *)child_elf_start;
    u64 vspace_slot, cnode_slot, ntfn_slot, tcb_slot;
    u64 irq_handler_slot;
    u64 pt_untyped, seg_untyped;
    u64 l2_slot, l1_slot, l0_code_slot, l0_ipc_slot, root_l0_slot;
    u64 ipc_frame_slot;
    u64 ram;
    u64 entry;
    int i;

    ipc_buf = bi_word(rt_bootinfo, BI_IPCBUF);

    if (eh->e_ident[0] != 0x7f || eh->e_ident[1] != 'E' ||
        eh->e_ident[2] != 'L' || eh->e_ident[3] != 'F' ||
        eh->e_ident[4] != 2 /* ELFCLASS64 */ ||
        eh->e_ident[5] != 1 /* ELFDATA2LSB */ ||
        eh->e_type != 2 /* ET_EXEC */ || eh->e_machine != 183 /* EM_AARCH64 */)
        return 0;

    /* 1. Bring the device up in the ROOT VSpace (MMIO + DMA + queues). */
    if (!virtio_net_init_device()) return 0;

    /* 2. Child VSpace (root page table + ASID). */
    vspace_slot = vspace_new();
    if (vspace_slot == 0) return 0;

    /* 3. Page tables: L2 + L1 (shared across the low region) + two L0 leaves
     *    (code @0x400000, IPC @0x900000) in the child VSpace, plus an L0 at
     *    COPY_VA in the root VSpace for the segment-copy scratch. */
    pt_untyped = find_ram_untyped(15 /* 5 x 4 KiB */);
    if (pt_untyped == (u64)-1) return 0;
    mark_untyped_used(pt_untyped);

    l2_slot      = next_slot++;
    l1_slot      = next_slot++;
    l0_code_slot = next_slot++;
    l0_ipc_slot  = next_slot++;
    root_l0_slot = next_slot++;

    if (retype_object(pt_untyped, CAP_ROOT_CNODE, l2_slot, OBJ_PAGE_TABLE, 12) != 0) return 0;
    if (retype_object(pt_untyped, CAP_ROOT_CNODE, l1_slot, OBJ_PAGE_TABLE, 12) != 0) return 0;
    if (retype_object(pt_untyped, CAP_ROOT_CNODE, l0_code_slot, OBJ_PAGE_TABLE, 12) != 0) return 0;
    if (retype_object(pt_untyped, CAP_ROOT_CNODE, l0_ipc_slot, OBJ_PAGE_TABLE, 12) != 0) return 0;
    if (retype_object(pt_untyped, CAP_ROOT_CNODE, root_l0_slot, OBJ_PAGE_TABLE, 12) != 0) return 0;

    /* Child VSpace: L2 + L1, then the two L0 leaves. */
    if (map_page_table(l2_slot, vspace_slot, CHILD_ELF_VA) != 0) return 0;
    if (map_page_table(l1_slot, vspace_slot, CHILD_ELF_VA) != 0) return 0;
    if (map_page_table(l0_code_slot, vspace_slot, CHILD_ELF_VA) != 0) return 0;
    if (map_page_table(l0_ipc_slot, vspace_slot, CHILD_IPC_BUF_VA) != 0) return 0;

    /* Root VSpace: L0 at COPY_VA for the segment-copy scratch. */
    if (map_page_table(root_l0_slot, CAP_ROOT_VSPACE, COPY_VA) != 0) return 0;

    /* 4. Hand the device + DMA frame to the child VSpace (unmap from the root
     *    VSpace, map into the child VSpace at the same VAs). */
    if (unmap_frame(dev_page_cap) != 0) return 0;
    if (map_frame(dev_page_cap, vspace_slot, 0x200000, RIGHTS_RW, 0 /* device, uncached */) != 0) return 0;
    if (unmap_frame(dma_page_cap) != 0) return 0;
    if (map_frame(dma_page_cap, vspace_slot, 0x600000, RIGHTS_RW, 0 /* DMA, uncached */) != 0) return 0;

    /* 5. Load the child ELF segments (driver + protocol code). */
    seg_untyped = find_ram_untyped(17 /* >= 128 KiB */);
    if (seg_untyped == (u64)-1) return 0;
    mark_untyped_used(seg_untyped);

    entry = eh->e_entry;
    for (i = 0; i < eh->e_phnum; i++) {
        const struct elf64_phdr *ph = (const struct elf64_phdr *)
            (child_elf_start + eh->e_phoff + (u64)i * eh->e_phentsize);
        if (ph->p_type != 1 /* PT_LOAD */) continue;
        if (!elf_load_segment(vspace_slot, seg_untyped, child_elf_start, ph)) return 0;
    }

    /* 6. Child IPC buffer: a 4 KiB frame at CHILD_IPC_BUF_VA. */
    ram = find_ram_untyped(12);
    if (ram == (u64)-1) return 0;
    mark_untyped_used(ram);
    ipc_frame_slot = next_slot++;
    if (retype_object(ram, CAP_ROOT_CNODE, ipc_frame_slot, OBJ_SMALL_PAGE, 12) != 0) return 0;
    if (map_frame(ipc_frame_slot, vspace_slot, CHILD_IPC_BUF_VA, RIGHTS_RW, ATTR_CACHEABLE) != 0) return 0;

    /* 7. Child CSpace: 16-slot CNode. */
    cnode_slot = next_slot++;
    ntfn_slot  = next_slot++;
    tcb_slot   = next_slot++;

    ram = find_ram_untyped(9 /* radix 4 CNode = 512 B */);
    if (ram == (u64)-1) return 0;
    mark_untyped_used(ram);
    if (retype_cnode(ram, cnode_slot, NET_CHILD_CNODE_RADIX) != 0) return 0;

    /* Slot 0 = self CNode. */
    if (sel4_cnode_mint(cnode_slot, 0, NET_CHILD_CNODE_RADIX,
                        CAP_ROOT_CNODE, cnode_slot, ROOT_CNODE_DEPTH, 3, 0) != 0) return 0;

    /* Slot 1 = RAM untyped (for the child's IRQ objects). */
    ram = find_ram_untyped(12);
    if (ram == (u64)-1) return 0;
    mark_untyped_used(ram);
    if (sel4_cnode_mint(cnode_slot, 1, NET_CHILD_CNODE_RADIX,
                        CAP_ROOT_CNODE, ram, ROOT_CNODE_DEPTH, 3, 0) != 0) return 0;

    /* Slot 2 = IRQ handler. */
    irq_handler_slot = next_slot++;
    if (sel4_irq_control_get(4 /* seL4_CapIRQControl */, VIRTIO_MMIO_IRQ,
                             irq_handler_slot, ROOT_CNODE_DEPTH) != 0) return 0;
    if (sel4_cnode_mint(cnode_slot, 2, NET_CHILD_CNODE_RADIX,
                        CAP_ROOT_CNODE, irq_handler_slot, ROOT_CNODE_DEPTH, 3, 0) != 0) return 0;

    /* Slot 3 = the child's own VSpace. */
    if (sel4_cnode_mint(cnode_slot, 3, NET_CHILD_CNODE_RADIX,
                        CAP_ROOT_CNODE, vspace_slot, ROOT_CNODE_DEPTH, 3, 0) != 0) return 0;

    /* Slot 4 = result notification (badged 42). */
    ram = find_ram_untyped(5);
    if (ram == (u64)-1) return 0;
    mark_untyped_used(ram);
    if (retype_notification(ram, ntfn_slot) != 0) return 0;
    if (sel4_cnode_mint(cnode_slot, 4, NET_CHILD_CNODE_RADIX,
                        CAP_ROOT_CNODE, ntfn_slot, ROOT_CNODE_DEPTH, 3, CHILD_BADGE) != 0) return 0;

    /* 8. Child TCB: own CSpace + own VSpace + IPC buffer, entry = ELF entry. */
    ram = find_ram_untyped(11);
    if (ram == (u64)-1) return 0;
    mark_untyped_used(ram);
    if (retype_tcb(ram, tcb_slot) != 0) return 0;

    if (sel4_tcb_configure(tcb_slot, 0 /* fault_ep */, cnode_slot, 0,
                           vspace_slot, 0, CHILD_IPC_BUF_VA, ipc_frame_slot) != 0)
        return 0;
    if (sel4_tcb_write_registers(tcb_slot, entry, 0 /* sp set by child entry */) != 0)
        return 0;

    /* 9. Wait for the child's result and return its badge. */
    return sel4_wait(ntfn_slot);
}

