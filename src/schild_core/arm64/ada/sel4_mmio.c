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

typedef unsigned long long u64;
typedef unsigned int       u32;
typedef unsigned short     u16;
typedef unsigned char      u8;

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
    u64 end   = bi_word(bi, BI_UNTYPED_END);
    u64 slot;

    for (slot = start; slot < end; slot++) {
        u64 desc     = bi + BI_UNTYPED_LIST + (slot - start) * 16;
        u64 paddr    = ((volatile u64 *)(desc + 0))[0];
        u64 sizebits = ((volatile unsigned char *)(desc + 8))[0];
        u64 isdev    = ((volatile unsigned char *)(desc + 9))[0];

        if (!isdev && sizebits >= 21) {
            u64 target = next_slot++;
            if (retype_large_page(slot, target) != 0) return 0;
            if (map_page(target, vaddr) != 0) return 0;
            return paddr;
        }
    }
    return 0;
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

/* Our MAC (matches the -device virtio-net-device,mac=... command line). */
static const u8 net_mac[6] = { 0x52, 0x54, 0x00, 0x12, 0x34, 0x56 };

/* Build an Ethernet + ARP request (42 bytes) for the SLIRP gateway (10.0.2.2).
 * This elicits a deterministic ARP reply from QEMU's user-mode netdev. */
static void build_arp_request(volatile u8 *pkt)
{
    static const u8 gateway_ip[4] = { 10, 0, 2, 2 };
    static const u8 guest_ip[4]   = { 10, 0, 2, 15 };
    int i;

    for (i = 0; i < 6; i++) pkt[i] = 0xff;               /* dst = broadcast */
    for (i = 0; i < 6; i++) pkt[6 + i] = net_mac[i];     /* src = our MAC */
    pkt[12] = 0x08; pkt[13] = 0x06;                       /* EtherType = ARP */
    pkt[14] = 0x00; pkt[15] = 0x01;                       /* htype = Ethernet */
    pkt[16] = 0x08; pkt[17] = 0x00;                       /* ptype = IPv4 */
    pkt[18] = 0x06;                                        /* hlen = 6 */
    pkt[19] = 0x04;                                        /* plen = 4 */
    pkt[20] = 0x00; pkt[21] = 0x01;                       /* op = request */
    for (i = 0; i < 6; i++) pkt[22 + i] = net_mac[i];     /* sender MAC */
    for (i = 0; i < 4; i++) pkt[28 + i] = guest_ip[i];    /* sender IP */
    for (i = 0; i < 6; i++) pkt[32 + i] = 0x00;           /* target MAC */
    for (i = 0; i < 4; i++) pkt[38 + i] = gateway_ip[i];  /* target IP */
}

/* Set up RX (queue 0) and TX (queue 1), send an ARP request, and check that the
 * device both consumes the TX and delivers the ARP reply into RX.  Returns:
 *   2 = TX + RX ok, 1 = TX ok (no RX), 0 = error. */
u64 schild_virtio_net_test(void)
{
    volatile u32 *regs;
    u64 dma_pa;
    volatile u8 *dma;
    volatile struct vring_desc *rx_desc, *tx_desc;
    volatile struct vring_avail *rx_avail, *tx_avail;
    volatile struct vring_used *rx_used, *tx_used;
    volatile u8 *pkt;
    int i, spins;
    u64 tx_ok, rx_ok;

    regs = get_dev_regs();
    if (regs == 0 || regs[0] != 0x74726976u) return 0;

    /* Reset + ACKNOWLEDGE + DRIVER + FEATURES_OK. */
    mmio32w(regs, VMMIO_STATUS, 0);
    mmio32w(regs, VMMIO_STATUS, VIRTIO_STATUS_ACKNOWLEDGE);
    mmio32w(regs, VMMIO_STATUS, VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER);
    mmio32w(regs, 0x024, 0);                 /* DriverFeaturesSel = page 0 */
    mmio32w(regs, VMMIO_DRIVER_FEATURES, 1u << 5);  /* accept VIRTIO_NET_F_MAC */
    mmio32w(regs, VMMIO_STATUS,
            VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER | VIRTIO_STATUS_FEATURES_OK);
    mmio32w(regs, 0x028, 4096);   /* GuestPageSize (legacy) */

    /* Allocate a 2 MiB DMA frame. */
    dma_pa = alloc_dma_2m(0x600000ULL);
    if (dma_pa == 0) return 0;
    dma = (volatile u8 *)0x600000ULL;

    /* RX queue (index 0) at DMA offset 0 (desc/avail in page 0, used in page 1). */
    setup_queue(regs, 0, dma_pa, VQ_NUM);
    rx_desc  = (volatile struct vring_desc *)(dma + 0);
    rx_avail = (volatile struct vring_avail *)(dma + vring_avail_off(VQ_NUM));
    rx_used  = (volatile struct vring_used *)(dma + vring_used_off(VQ_NUM));

    /* TX queue (index 1) at DMA offset 0x4000 (2 pages past RX). */
    setup_queue(regs, 1, dma_pa + 0x4000, VQ_NUM);
    tx_desc  = (volatile struct vring_desc *)(dma + 0x4000);
    tx_avail = (volatile struct vring_avail *)(dma + 0x4000 + vring_avail_off(VQ_NUM));
    tx_used  = (volatile struct vring_used *)(dma + 0x4000 + vring_used_off(VQ_NUM));

    /* RX: one empty buffer the device may write into (virtio_net_hdr + frame). */
    rx_desc[0].addr  = dma_pa + 0x2000;   /* buffer past the RX used ring */
    rx_desc[0].len   = 1510;
    rx_desc[0].flags = 2;   /* WRITE: device writes into the buffer */
    rx_desc[0].next  = 0;
    rx_avail->ring[0] = 0;
    rx_avail->idx = 1;

    /* TX: a 10-byte virtio_net_hdr + an ARP request (60-byte Ethernet frame). */
    pkt = dma + 0x6000;                     /* past the TX used ring */
    for (i = 0; i < 10; i++) pkt[i] = 0x00; /* virtio_net_hdr (no offloads) */
    build_arp_request(pkt + 10);
    for (i = 52; i < 70; i++) pkt[i] = 0x00;/* pad Ethernet frame to 60 bytes */
    tx_desc[0].addr  = dma_pa + 0x6000;
    tx_desc[0].len   = 70;
    tx_desc[0].flags = 0;
    tx_desc[0].next  = 0;
    tx_avail->ring[0] = 0;
    tx_avail->idx = 1;
    __asm__ volatile("dmb sy" ::: "memory");

    /* DRIVER_OK, then kick RX and TX. */
    mmio32w(regs, VMMIO_STATUS,
            VIRTIO_STATUS_ACKNOWLEDGE | VIRTIO_STATUS_DRIVER |
            VIRTIO_STATUS_FEATURES_OK | VIRTIO_STATUS_DRIVER_OK);
    mmio32w(regs, VMMIO_QUEUE_NOTIFY, 0);   /* kick RX (queue 0) */
    mmio32w(regs, VMMIO_QUEUE_NOTIFY, 1);   /* kick TX (queue 1) */

    for (spins = 0; spins < 1000000; spins++) {
        if (tx_used->idx >= 1) break;
    }
    tx_ok = (tx_used->idx >= 1);

    /* Poll RX for the ARP reply. */
    for (spins = 0; spins < 5000000 && rx_used->idx < 1; spins++) {
    }
    rx_ok = (rx_used->idx >= 1);
    if (rx_ok) {
        /* Skip the 10-byte virtio_net_hdr and verify it is an ARP reply. */
        volatile u8 *rxpkt = dma + 0x2000 + 10;
        if (rxpkt[12] != 0x08 || rxpkt[13] != 0x06 ||   /* EtherType = ARP  */
            rxpkt[20] != 0x00 || rxpkt[21] != 0x02) {   /* opcode = reply  */
            rx_ok = 0;
        }
    }

    return rx_ok ? 2 : (tx_ok ? 1 : 0);
}
