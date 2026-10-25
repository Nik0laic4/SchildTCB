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

/* 16-bit one's-complement checksum over `data` (network byte order). */
static u16 csum16(const volatile u8 *data, int len)
{
    u32 sum = 0;
    int i;

    for (i = 0; i + 1 < len; i += 2)
        sum += ((u32)data[i] << 8) | (u32)data[i + 1];
    if (i < len)
        sum += (u32)data[i] << 8;
    while (sum >> 16)
        sum = (sum & 0xffff) + (sum >> 16);
    return (u16)~sum;
}

/* Build a 20-byte IPv4 header (checksum computed). */
static void build_ipv4(volatile u8 *p, int total_len, int proto,
                       const u8 *src_ip, const u8 *dst_ip)
{
    int i;
    u16 c;

    p[0] = 0x45;                       /* version 4, IHL 5 */
    p[1] = 0x00;                       /* TOS */
    p[2] = (u8)(total_len >> 8);
    p[3] = (u8)total_len;
    p[4] = 0x00; p[5] = 0x01;          /* identification */
    p[6] = 0x00; p[7] = 0x00;          /* flags + fragment offset */
    p[8] = 0x40;                       /* TTL = 64 */
    p[9] = (u8)proto;                  /* 1 = ICMP */
    p[10] = 0x00; p[11] = 0x00;        /* checksum */
    for (i = 0; i < 4; i++) p[12 + i] = src_ip[i];
    for (i = 0; i < 4; i++) p[16 + i] = dst_ip[i];
    c = csum16(p, 20);
    p[10] = (u8)(c >> 8);
    p[11] = (u8)c;
}

/* Build an ICMP echo request (header + payload, checksum computed). */
static void build_icmp_echo(volatile u8 *p, const char *payload, int plen)
{
    int i;
    u16 c;

    p[0] = 0x08;                       /* type = echo request */
    p[1] = 0x00;                       /* code */
    p[2] = 0x00; p[3] = 0x00;          /* checksum */
    p[4] = 0x12; p[5] = 0x34;          /* identifier */
    p[6] = 0x00; p[7] = 0x01;          /* sequence number */
    for (i = 0; i < plen; i++) p[8 + i] = (u8)payload[i];
    c = csum16(p, 8 + plen);
    p[2] = (u8)(c >> 8);
    p[3] = (u8)c;
}

/* Build an Ethernet + IPv4 + ICMP echo request (50 bytes) to `dst_mac`. */
static void build_icmp_frame(volatile u8 *pkt, const u8 *dst_mac)
{
    static const u8 gw_ip[4]    = { 10, 0, 2, 2 };
    static const u8 guest_ip[4] = { 10, 0, 2, 15 };
    int i;

    for (i = 0; i < 6; i++) pkt[i] = dst_mac[i];      /* dst MAC = gateway */
    for (i = 0; i < 6; i++) pkt[6 + i] = net_mac[i];  /* src MAC = ours */
    pkt[12] = 0x08; pkt[13] = 0x00;                    /* EtherType = IPv4 */
    build_ipv4(pkt + 14, 20 + 8 + 8, 1, guest_ip, gw_ip);
    build_icmp_echo(pkt + 14 + 20, "SchildTC", 8);
}

/* Extract the gateway MAC from an ARP reply (Ethernet frame, no virtio_net_hdr).
 * Returns 1 on success. */
static int parse_arp_reply(const volatile u8 *rxpkt, u8 *gw_mac)
{
    int i;

    if (rxpkt[12] != 0x08 || rxpkt[13] != 0x06) return 0;  /* EtherType = ARP */
    if (rxpkt[20] != 0x00 || rxpkt[21] != 0x02) return 0;  /* opcode = reply  */
    for (i = 0; i < 6; i++) gw_mac[i] = rxpkt[22 + i];     /* sender MAC     */
    return 1;
}

/* Verify a received Ethernet frame is an ICMP echo reply. */
static int verify_icmp_reply(const volatile u8 *rxpkt)
{
    if (rxpkt[12] != 0x08 || rxpkt[13] != 0x00) return 0;  /* EtherType = IPv4 */
    if (rxpkt[14 + 9] != 0x01) return 0;                    /* protocol = ICMP */
    if (rxpkt[14 + 20] != 0x00) return 0;                   /* type = echo reply */
    return 1;
}

/* Build a UDP datagram (8-byte header + payload, checksum computed over the
 * IPv4 pseudo-header). */
static void build_udp(volatile u8 *p, u16 sport, u16 dport,
                      const u8 *src_ip, const u8 *dst_ip,
                      const volatile u8 *payload, int plen)
{
    u32 sum = 0;
    u16 c;
    int i;

    p[0] = (u8)(sport >> 8); p[1] = (u8)sport;
    p[2] = (u8)(dport >> 8); p[3] = (u8)dport;
    p[4] = (u8)((8 + plen) >> 8); p[5] = (u8)(8 + plen);
    p[6] = 0x00; p[7] = 0x00;
    for (i = 0; i < plen; i++) p[8 + i] = payload[i];

    /* Pseudo-header: src IP, dst IP, zero+protocol, UDP length. */
    for (i = 0; i < 4; i += 2) sum += ((u32)src_ip[i] << 8) | src_ip[i + 1];
    for (i = 0; i < 4; i += 2) sum += ((u32)dst_ip[i] << 8) | dst_ip[i + 1];
    sum += 17;
    sum += 8 + plen;
    for (i = 0; i + 1 < 8 + plen; i += 2)
        sum += ((u32)p[i] << 8) | p[i + 1];
    if (i < 8 + plen)
        sum += (u32)p[i] << 8;
    while (sum >> 16)
        sum = (sum & 0xffff) + (sum >> 16);
    c = (u16)~sum;
    if (c == 0) c = 0xffff;
    p[6] = (u8)(c >> 8);
    p[7] = (u8)c;
}

/* Build a BOOTP/DHCP DISCOVER message (300 bytes). */
static void build_dhcp_discover(volatile u8 *p)
{
    int i;

    for (i = 0; i < 300; i++) p[i] = 0x00;
    p[0] = 0x01;             /* op = BOOTREQUEST */
    p[1] = 0x01;             /* htype = Ethernet */
    p[2] = 0x06;             /* hlen = 6 */
    p[4] = 0x12; p[5] = 0x34; p[6] = 0x56; p[7] = 0x78;   /* xid */
    p[10] = 0x80;            /* flags = broadcast */
    for (i = 0; i < 6; i++) p[28 + i] = net_mac[i];        /* chaddr */
    p[236] = 0x63; p[237] = 0x82; p[238] = 0x53; p[239] = 0x63;  /* cookie */
    p[240] = 53; p[241] = 1; p[242] = 1;   /* option 53: message type = DISCOVER */
    p[243] = 255;                           /* option 255: end */
}

/* Build an Ethernet + IPv4 + UDP + DHCP DISCOVER frame (342 bytes). */
static void build_dhcp_frame(volatile u8 *pkt)
{
    static const u8 zero_ip[4]  = { 0, 0, 0, 0 };
    static const u8 bcast_ip[4] = { 255, 255, 255, 255 };
    volatile u8 *udp  = pkt + 14 + 20;
    volatile u8 *dhcp = udp + 8;
    int i;

    for (i = 0; i < 6; i++) pkt[i] = 0xff;              /* dst = broadcast */
    for (i = 0; i < 6; i++) pkt[6 + i] = net_mac[i];    /* src = our MAC */
    pkt[12] = 0x08; pkt[13] = 0x00;                      /* EtherType = IPv4 */

    build_dhcp_discover(dhcp);
    build_udp(udp, 68, 67, zero_ip, bcast_ip, dhcp, 300);
    build_ipv4(pkt + 14, 20 + 8 + 300, 17, zero_ip, bcast_ip);
}

/* Extract the offered IP (yiaddr) from a received DHCP OFFER. */
static int parse_dhcp_offer(const volatile u8 *rxpkt, u8 *offered_ip)
{
    int i;

    if (rxpkt[12] != 0x08 || rxpkt[13] != 0x00) return 0;  /* EtherType = IPv4 */
    if (rxpkt[23] != 0x11) return 0;                        /* proto = UDP */
    if (rxpkt[36] != 0x00 || rxpkt[37] != 0x44) return 0;   /* UDP dport = 68 */
    if (rxpkt[42] != 0x02) return 0;                        /* DHCP op = BOOTREPLY */
    for (i = 0; i < 4; i++) offered_ip[i] = rxpkt[42 + 16 + i];  /* yiaddr */
    return 1;
}

/* Build a TCP segment (20-byte header + payload, checksum computed over the
 * IPv4 pseudo-header). */
static void build_tcp(volatile u8 *p, u16 sport, u16 dport,
                      u32 seq, u32 ack, u8 flags,
                      const u8 *src_ip, const u8 *dst_ip,
                      const volatile u8 *payload, int plen)
{
    u32 sum = 0;
    u16 c;
    int i;

    p[0] = (u8)(sport >> 8); p[1] = (u8)sport;
    p[2] = (u8)(dport >> 8); p[3] = (u8)dport;
    p[4] = (u8)(seq >> 24); p[5] = (u8)(seq >> 16);
    p[6] = (u8)(seq >> 8); p[7] = (u8)seq;
    p[8] = (u8)(ack >> 24); p[9] = (u8)(ack >> 16);
    p[10] = (u8)(ack >> 8); p[11] = (u8)ack;
    p[12] = 0x50;            /* data offset = 5 words (20 bytes) */
    p[13] = flags;
    p[14] = 0x20; p[15] = 0x00;   /* window = 8192 */
    p[16] = 0x00; p[17] = 0x00;   /* checksum */
    p[18] = 0x00; p[19] = 0x00;   /* urgent pointer */
    for (i = 0; i < plen; i++) p[20 + i] = payload[i];

    /* Pseudo-header: src IP, dst IP, zero+protocol(6), TCP length. */
    for (i = 0; i < 4; i += 2) sum += ((u32)src_ip[i] << 8) | src_ip[i + 1];
    for (i = 0; i < 4; i += 2) sum += ((u32)dst_ip[i] << 8) | dst_ip[i + 1];
    sum += 6;
    sum += 20 + plen;
    for (i = 0; i + 1 < 20 + plen; i += 2)
        sum += ((u32)p[i] << 8) | p[i + 1];
    if (i < 20 + plen)
        sum += (u32)p[i] << 8;
    while (sum >> 16)
        sum = (sum & 0xffff) + (sum >> 16);
    c = (u16)~sum;
    p[16] = (u8)(c >> 8);
    p[17] = (u8)c;
}

/* Build an Ethernet + IPv4 + TCP segment. */
static void build_tcp_frame(volatile u8 *pkt, const u8 *dst_mac,
                            const u8 *src_ip, const u8 *dst_ip,
                            u16 sport, u16 dport,
                            u32 seq, u32 ack, u8 flags,
                            const volatile u8 *payload, int plen)
{
    int i;

    for (i = 0; i < 6; i++) pkt[i] = dst_mac[i];
    for (i = 0; i < 6; i++) pkt[6 + i] = net_mac[i];
    pkt[12] = 0x08; pkt[13] = 0x00;   /* EtherType = IPv4 */
    build_tcp(pkt + 14 + 20, sport, dport, seq, ack, flags,
              src_ip, dst_ip, payload, plen);
    build_ipv4(pkt + 14, 20 + 20 + plen, 6, src_ip, dst_ip);
}

/* Parse a received TCP segment; fills seq/ack/flags/payload on success. */
static int parse_tcp(const volatile u8 *rxpkt, u32 *seq, u32 *ack, u8 *flags,
                     const volatile u8 **payload, int *plen)
{
    int ihl, doff, total;
    const volatile u8 *tcp;

    if (rxpkt[12] != 0x08 || rxpkt[13] != 0x00) return 0;   /* EtherType = IPv4 */
    if (rxpkt[23] != 0x06) return 0;                         /* proto = TCP */
    ihl = (rxpkt[14] & 0x0f) * 4;
    tcp = rxpkt + 14 + ihl;
    doff = (tcp[12] >> 4) * 4;
    *seq   = ((u32)tcp[4] << 24) | ((u32)tcp[5] << 16) | ((u32)tcp[6] << 8) | tcp[7];
    *ack   = ((u32)tcp[8] << 24) | ((u32)tcp[9] << 16) | ((u32)tcp[10] << 8) | tcp[11];
    *flags = tcp[13];
    *payload = tcp + doff;
    total = ((u16)rxpkt[16] << 8) | rxpkt[17];
    *plen = total - ihl - doff;
    if (*plen < 0) *plen = 0;
    return 1;
}

extern void schild_sel4_debug_putchar(char c);

/* Print the HTTP response body (bytes after the "\r\n\r\n" separator). */
static void print_http_body(const volatile u8 *p, int len)
{
    int i, j;
    for (i = 0; i + 3 < len; i++) {
        if (p[i] == '\r' && p[i+1] == '\n' && p[i+2] == '\r' && p[i+3] == '\n') {
            schild_sel4_debug_putchar('[');
            schild_sel4_debug_putchar('b');
            schild_sel4_debug_putchar('o');
            schild_sel4_debug_putchar('d');
            schild_sel4_debug_putchar('y');
            schild_sel4_debug_putchar(']');
            schild_sel4_debug_putchar(' ');
            for (j = i + 4; j < len; j++) schild_sel4_debug_putchar((char)p[j]);
            schild_sel4_debug_putchar('\n');
            return;
        }
    }
}

static void put_dec(u8 v)
{
    if (v >= 100) schild_sel4_debug_putchar('0' + v / 100);
    if (v >= 10) schild_sel4_debug_putchar('0' + (v / 10) % 10);
    schild_sel4_debug_putchar('0' + v % 10);
}

/* Build a DNS A query for "example.com" (29 bytes). */
static void build_dns_query(volatile u8 *p)
{
    int i = 0;
    p[i++] = 0x12; p[i++] = 0x34;   /* ID */
    p[i++] = 0x01; p[i++] = 0x00;   /* flags: RD */
    p[i++] = 0x00; p[i++] = 0x01;   /* QDCOUNT = 1 */
    p[i++] = 0x00; p[i++] = 0x00;   /* ANCOUNT */
    p[i++] = 0x00; p[i++] = 0x00;   /* NSCOUNT */
    p[i++] = 0x00; p[i++] = 0x00;   /* ARCOUNT */
    p[i++] = 7;
    p[i++] = 'e'; p[i++] = 'x'; p[i++] = 'a'; p[i++] = 'm'; p[i++] = 'p'; p[i++] = 'l'; p[i++] = 'e';
    p[i++] = 3;
    p[i++] = 'c'; p[i++] = 'o'; p[i++] = 'm';
    p[i++] = 0;                      /* name terminator */
    p[i++] = 0x00; p[i++] = 0x01;    /* QTYPE = A */
    p[i++] = 0x00; p[i++] = 0x01;    /* QCLASS = IN */
}

/* Build an Ethernet + IPv4 + UDP + DNS query to the SLIRP DNS server. */
static void build_dns_frame(volatile u8 *pkt, const u8 *dst_mac, const u8 *src_ip)
{
    static const u8 dns_ip[4] = { 10, 0, 2, 3 };
    volatile u8 *udp = pkt + 14 + 20;
    volatile u8 *dns = udp + 8;
    int i;

    for (i = 0; i < 6; i++) pkt[i] = dst_mac[i];      /* dst = gateway */
    for (i = 0; i < 6; i++) pkt[6 + i] = net_mac[i];  /* src = our MAC */
    pkt[12] = 0x08; pkt[13] = 0x00;                    /* EtherType = IPv4 */

    build_dns_query(dns);
    build_udp(udp, 53000, 53, src_ip, dns_ip, dns, 29);
    build_ipv4(pkt + 14, 20 + 8 + 29, 17, src_ip, dns_ip);
}

/* Verify a DNS reply and extract the resolved IPv4 address (last 4 bytes). */
static int parse_dns_reply(const volatile u8 *rxpkt, u8 *ip)
{
    const volatile u8 *dns;
    int udp_len, plen, i;

    if (rxpkt[12] != 0x08 || rxpkt[13] != 0x00) return 0;   /* EtherType = IPv4 */
    if (rxpkt[23] != 0x11) return 0;                         /* proto = UDP */
    if (rxpkt[34] != 0x00 || rxpkt[35] != 0x35) return 0;    /* UDP sport = 53 */
    dns = rxpkt + 42;                                        /* after Eth+IP+UDP */
    if (dns[0] != 0x12 || dns[1] != 0x34) return 0;          /* ID */
    if ((dns[2] & 0x80) == 0) return 0;                       /* QR = response */
    if ((dns[6] << 8 | dns[7]) == 0) return 0;               /* ANCOUNT > 0 */
    udp_len = ((u16)rxpkt[38] << 8) | rxpkt[39];
    plen = udp_len - 8;
    if (plen < 4) return 0;
    for (i = 0; i < 4; i++) ip[i] = dns[plen - 4 + i];
    return 1;
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

/* File-scope device/ring state (populated by net_init). */
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

static inline void net_barrier(void)
{
    __asm__ volatile("dmb sy" ::: "memory");
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

/* Spin up to `timeout` iterations for one received frame. */
static int rx_wait(u32 timeout)
{
    u32 spins;
    for (spins = 0; spins < timeout; spins++) {
        int d = rx_poll();
        if (d >= 0) return d;
    }
    return -1;
}

/* Pointer to the Ethernet frame of a received descriptor (past the 10-byte
 * virtio_net_hdr). */
static const volatile u8 *rx_frame(int d)
{
    return (const volatile u8 *)(net_dma + RX_BUF_BASE + (u64)d * RX_BUF_STRIDE + 10);
}

/* Give a consumed RX buffer back to the device. */
static void rx_recycle(u16 d)
{
    rx_post(d);
    rx_kick();
}

/* Buffer for the next rotating TX descriptor. */
static volatile u8 *tx_buffer(void)
{
    return (volatile u8 *)(net_dma + TX_BUF_BASE + (u64)net_tx_next * TX_BUF_STRIDE);
}

/* Submit the current TX buffer (len bytes incl. virtio_net_hdr) and wait for
 * the device to consume it.  Returns 1 on success, 0 on timeout. */
static int tx_send(u32 len)
{
    u16 d = net_tx_next;
    u32 spins;

    net_tx_desc[d].addr  = net_dma_pa + TX_BUF_BASE + (u64)d * TX_BUF_STRIDE;
    net_tx_desc[d].len   = len;
    net_tx_desc[d].flags = 0;
    net_tx_desc[d].next  = 0;
    net_tx_avail->ring[net_tx_avail->idx % VQ_NUM] = d;
    net_tx_avail->idx = (u16)(net_tx_avail->idx + 1);
    net_barrier();
    mmio32w(net_regs, VMMIO_QUEUE_NOTIFY, 1);

    for (spins = 0; spins < 1000000; spins++) {
        if (net_tx_used->idx > net_tx_last_used) break;
    }
    if (net_tx_used->idx <= net_tx_last_used) return 0;
    net_tx_last_used = (u16)(net_tx_last_used + 1);
    net_tx_next = (u16)((d + 1) % VQ_NUM);
    return 1;
}

/* Reset + feature negotiation + queue setup + RX pool.  Returns 1 on success. */
static int net_init(void)
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

/* Run the minimal TCP/IP stack end-to-end over the virtio-net device:
 * ARP -> ICMP echo -> DHCP -> TCP client + HTTP GET -> TCP server (hostfwd)
 * -> DNS A query.  Returns (same contract as before):
 *   7 = DNS ok, 6 = TCP server ok (no DNS), 5 = HTTP ok (no server),
 *   4 = DHCP ok (no TCP), 3 = ping ok (no DHCP), 2 = ARP ok (no ICMP),
 *   1 = TX ok, 0 = error. */
u64 schild_virtio_net_test(void)
{
    u8 gw_mac[6];
    u8 offered_ip[4];
    int d;
    u32 spins;

    if (!net_init()) return 0;

    /* ARP: resolve the SLIRP gateway (10.0.2.2). */
    {
        volatile u8 *pkt = tx_buffer();
        int i;
        for (i = 0; i < 10; i++) pkt[i] = 0x00;   /* virtio_net_hdr */
        build_arp_request(pkt + 10);
        for (i = 52; i < 70; i++) pkt[i] = 0x00;   /* pad to 60 bytes */
        if (!tx_send(70)) return 0;
    }
    d = rx_wait(5000000);
    if (d < 0) return 1;
    if (!parse_arp_reply(rx_frame(d), gw_mac)) { rx_recycle((u16)d); return 1; }
    rx_recycle((u16)d);

    /* ICMP echo (ping). */
    {
        volatile u8 *pkt = tx_buffer();
        int i;
        for (i = 0; i < 10; i++) pkt[i] = 0x00;
        build_icmp_frame(pkt + 10, gw_mac);
        for (i = 60; i < 70; i++) pkt[i] = 0x00;   /* pad to 60 bytes */
        if (!tx_send(70)) return 2;
    }
    d = rx_wait(5000000);
    if (d < 0) return 2;
    if (!verify_icmp_reply(rx_frame(d))) { rx_recycle((u16)d); return 2; }
    rx_recycle((u16)d);

    /* DHCP DISCOVER (UDP broadcast). */
    {
        volatile u8 *pkt = tx_buffer();
        int i;
        for (i = 0; i < 10; i++) pkt[i] = 0x00;
        build_dhcp_frame(pkt + 10);
        if (!tx_send(10 + 342)) return 3;
    }
    d = rx_wait(5000000);
    if (d < 0) return 3;
    if (!parse_dhcp_offer(rx_frame(d), offered_ip)) { rx_recycle((u16)d); return 3; }
    rx_recycle((u16)d);

    /* TCP client: SYN -> SYN-ACK -> ACK + HTTP/1.0 GET. */
    {
        static const u8 host_ip[4] = { 10, 0, 2, 2 };
        static const u8 http_get[18] = "GET / HTTP/1.0\r\n\r\n";
        const u32 isn = 0x12345678u;
        u32 server_isn = 0;

        /* SYN. */
        {
            volatile u8 *pkt = tx_buffer();
            int i;
            for (i = 0; i < 10; i++) pkt[i] = 0x00;
            build_tcp_frame(pkt + 10, gw_mac, offered_ip, host_ip,
                            12345, 8080, isn, 0, 0x02, 0, 0);
            if (!tx_send(10 + 14 + 20 + 20)) return 4;
        }
        d = rx_wait(5000000);
        if (d < 0) return 4;
        {
            const volatile u8 *f = rx_frame(d);
            const volatile u8 *tpayload;
            u32 seq, ack; u8 fl; int pl;
            if (!parse_tcp(f, &seq, &ack, &fl, &tpayload, &pl) ||
                (fl & 0x12) != 0x12 || ack != isn + 1) {
                rx_recycle((u16)d);
                return 4;
            }
            server_isn = seq;
        }
        rx_recycle((u16)d);

        /* ACK + HTTP GET.  The server replies with a pure ACK first, then the
         * HTTP response. */
        {
            volatile u8 *pkt = tx_buffer();
            int i;
            for (i = 0; i < 10; i++) pkt[i] = 0x00;
            build_tcp_frame(pkt + 10, gw_mac, offered_ip, host_ip,
                            12345, 8080, isn + 1, server_isn + 1, 0x18, http_get, 18);
            if (!tx_send(10 + 14 + 20 + 20 + 18)) return 4;
        }
        {
            int tries, ok = 0;
            for (tries = 0; tries < 4 && !ok; tries++) {
                d = rx_wait(5000000);
                if (d < 0) break;
                {
                    const volatile u8 *f = rx_frame(d);
                    const volatile u8 *tpayload;
                    u32 seq2, ack2; u8 fl2; int pl2;
                    if (parse_tcp(f, &seq2, &ack2, &fl2, &tpayload, &pl2) &&
                        (fl2 & 0x10) && pl2 >= 5 &&
                        tpayload[0] == 'H' && tpayload[1] == 'T' &&
                        tpayload[2] == 'T' && tpayload[3] == 'P' &&
                        tpayload[4] == '/') {
                        ok = 1;
                        print_http_body(tpayload, pl2);
                    }
                }
                rx_recycle((u16)d);
            }
            if (!ok) return 4;
        }
    }

    /* TCP server: passive open on port 8081 (the host connects via hostfwd). */
    {
        static const u8 host_ip[4] = { 10, 0, 2, 2 };
        const u32 sisn = 0x87654321u;
        u32 client_isn = 0;
        u16 client_port = 0;

        /* Wait for an incoming SYN, ignoring the HTTP server's retransmits. */
        {
            int found = 0;
            for (spins = 0; spins < 2000000000 && !found; spins++) {
                d = rx_poll();
                if (d < 0) continue;
                {
                    const volatile u8 *f = rx_frame(d);
                    const volatile u8 *tpayload;
                    u32 seq, ack; u8 fl; int pl;
                    if (parse_tcp(f, &seq, &ack, &fl, &tpayload, &pl) &&
                        (fl & 0x02) && !(fl & 0x10) &&
                        (((u16)f[36] << 8) | f[37]) == 8081) {
                        client_isn = seq;
                        client_port = ((u16)f[34] << 8) | f[35];
                        found = 1;
                    }
                }
                rx_recycle((u16)d);
            }
            if (!found) return 5;
        }

        /* SYN-ACK. */
        {
            volatile u8 *pkt = tx_buffer();
            int i;
            for (i = 0; i < 10; i++) pkt[i] = 0x00;
            build_tcp_frame(pkt + 10, gw_mac, offered_ip, host_ip,
                            8081, client_port, sisn, client_isn + 1, 0x12, 0, 0);
            if (!tx_send(10 + 14 + 20 + 20)) return 5;
        }

        /* Wait for the client ACK. */
        {
            int tries, ok = 0;
            for (tries = 0; tries < 4 && !ok; tries++) {
                d = rx_wait(5000000);
                if (d < 0) break;
                {
                    const volatile u8 *f = rx_frame(d);
                    const volatile u8 *tpayload;
                    u32 seq2, ack2; u8 fl2; int pl2;
                    if (parse_tcp(f, &seq2, &ack2, &fl2, &tpayload, &pl2) &&
                        (fl2 & 0x10) && !(fl2 & 0x02) && ack2 == sisn + 1 &&
                        (((u16)f[36] << 8) | f[37]) == 8081) {
                        ok = 1;
                    }
                }
                rx_recycle((u16)d);
            }
            if (!ok) return 5;
        }
    }

    /* DNS client: resolve "example.com" via SLIRP DNS (10.0.2.3). */
    {
        volatile u8 *pkt = tx_buffer();
        int i;
        for (i = 0; i < 10; i++) pkt[i] = 0x00;
        build_dns_frame(pkt + 10, gw_mac, offered_ip);
        if (!tx_send(10 + 14 + 20 + 8 + 29)) return 6;
    }
    {
        int found = 0;
        for (spins = 0; spins < 2000000000 && !found; spins++) {
            d = rx_poll();
            if (d < 0) continue;
            {
                const volatile u8 *f = rx_frame(d);
                u8 ip[4];
                if (parse_dns_reply(f, ip)) {
                    schild_sel4_debug_putchar('[');
                    schild_sel4_debug_putchar('d');
                    schild_sel4_debug_putchar('n');
                    schild_sel4_debug_putchar('s');
                    schild_sel4_debug_putchar(']');
                    schild_sel4_debug_putchar(' ');
                    put_dec(ip[0]); schild_sel4_debug_putchar('.');
                    put_dec(ip[1]); schild_sel4_debug_putchar('.');
                    put_dec(ip[2]); schild_sel4_debug_putchar('.');
                    put_dec(ip[3]);
                    schild_sel4_debug_putchar('\n');
                    found = 1;
                }
            }
            rx_recycle((u16)d);
        }
        if (!found) return 6;
    }

    return 7;
}
