/* Copyright (C) 2026 Alexander Irganov
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Schild TCB -- minimal TCP/IP stack test over the virtio-net driver.
 *
 * This is a protocol test harness (ARP -> ICMP -> DHCP -> TCP client/HTTP ->
 * TCP server -> DNS) driven through the virtio_net_* driver API.  It is NOT a
 * general-purpose TCP/IP stack: frames are built/parsed inline and received
 * TCP data is not ACKed.
 */
#include "virtio_net.h"

extern void schild_sel4_debug_putchar(char c);

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

/* Run the minimal TCP/IP stack end-to-end over the virtio-net device:
 * ARP -> ICMP echo -> DHCP -> TCP client + HTTP GET -> TCP server (hostfwd)
 * -> DNS A query.  Returns:
 *   7 = DNS ok, 6 = TCP server ok (no DNS), 5 = HTTP ok (no server),
 *   4 = DHCP ok (no TCP), 3 = ping ok (no DHCP), 2 = ARP ok (no ICMP),
 *   1 = TX ok, 0 = error. */
u64 schild_virtio_net_test(void)
{
    u8 gw_mac[6];
    u8 offered_ip[4];

    if (!virtio_net_init()) return 0;

    /* ARP: resolve the SLIRP gateway (10.0.2.2). */
    {
        volatile u8 *pkt = virtio_net_tx_buffer();
        int i;
        for (i = 0; i < 10; i++) pkt[i] = 0x00;
        build_arp_request(pkt + 10);
        for (i = 52; i < 70; i++) pkt[i] = 0x00;
        virtio_net_tx_send(70);
    }
    {
        const volatile u8 *f = virtio_net_rx();
        if (!parse_arp_reply(f, gw_mac)) { virtio_net_rx_done(); return 1; }
        virtio_net_rx_done();
    }

    /* ICMP echo (ping). */
    {
        volatile u8 *pkt = virtio_net_tx_buffer();
        int i;
        for (i = 0; i < 10; i++) pkt[i] = 0x00;
        build_icmp_frame(pkt + 10, gw_mac);
        for (i = 60; i < 70; i++) pkt[i] = 0x00;
        virtio_net_tx_send(70);
    }
    {
        const volatile u8 *f = virtio_net_rx();
        if (!verify_icmp_reply(f)) { virtio_net_rx_done(); return 2; }
        virtio_net_rx_done();
    }

    /* DHCP DISCOVER (UDP broadcast). */
    {
        volatile u8 *pkt = virtio_net_tx_buffer();
        int i;
        for (i = 0; i < 10; i++) pkt[i] = 0x00;
        build_dhcp_frame(pkt + 10);
        virtio_net_tx_send(10 + 342);
    }
    {
        const volatile u8 *f = virtio_net_rx();
        if (!parse_dhcp_offer(f, offered_ip)) { virtio_net_rx_done(); return 3; }
        virtio_net_rx_done();
    }

    /* TCP client: SYN -> SYN-ACK -> ACK + HTTP/1.0 GET. */
    {
        static const u8 host_ip[4] = { 10, 0, 2, 2 };
        static const u8 http_get[18] = "GET / HTTP/1.0\r\n\r\n";
        const u32 isn = 0x12345678u;
        u32 server_isn = 0;

        /* SYN. */
        {
            volatile u8 *pkt = virtio_net_tx_buffer();
            int i;
            for (i = 0; i < 10; i++) pkt[i] = 0x00;
            build_tcp_frame(pkt + 10, gw_mac, offered_ip, host_ip,
                            12345, 8080, isn, 0, 0x02, 0, 0);
            virtio_net_tx_send(10 + 14 + 20 + 20);
        }
        {
            const volatile u8 *f = virtio_net_rx();
            const volatile u8 *tpayload;
            u32 seq, ack; u8 fl; int pl;
            if (!parse_tcp(f, &seq, &ack, &fl, &tpayload, &pl) ||
                (fl & 0x12) != 0x12 || ack != isn + 1) {
                virtio_net_rx_done();
                return 4;
            }
            server_isn = seq;
        }
        virtio_net_rx_done();

        /* ACK + HTTP GET.  The server replies with a pure ACK first, then the
         * HTTP response. */
        {
            volatile u8 *pkt = virtio_net_tx_buffer();
            int i;
            for (i = 0; i < 10; i++) pkt[i] = 0x00;
            build_tcp_frame(pkt + 10, gw_mac, offered_ip, host_ip,
                            12345, 8080, isn + 1, server_isn + 1, 0x18, http_get, 18);
            virtio_net_tx_send(10 + 14 + 20 + 20 + 18);
        }
        {
            int ok = 0;
            for (;;) {
                const volatile u8 *f = virtio_net_rx();
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
                virtio_net_rx_done();
                if (ok) break;
            }
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
            for (;;) {
                const volatile u8 *f = virtio_net_rx();
                const volatile u8 *tpayload;
                u32 seq, ack; u8 fl; int pl;
                if (parse_tcp(f, &seq, &ack, &fl, &tpayload, &pl) &&
                    (fl & 0x02) && !(fl & 0x10) &&
                    (((u16)f[36] << 8) | f[37]) == 8081) {
                    client_isn = seq;
                    client_port = ((u16)f[34] << 8) | f[35];
                    found = 1;
                }
                virtio_net_rx_done();
                if (found) break;
            }
        }

        /* SYN-ACK. */
        {
            volatile u8 *pkt = virtio_net_tx_buffer();
            int i;
            for (i = 0; i < 10; i++) pkt[i] = 0x00;
            build_tcp_frame(pkt + 10, gw_mac, offered_ip, host_ip,
                            8081, client_port, sisn, client_isn + 1, 0x12, 0, 0);
            virtio_net_tx_send(10 + 14 + 20 + 20);
        }

        /* Wait for the client ACK. */
        {
            int ok = 0;
            for (;;) {
                const volatile u8 *f = virtio_net_rx();
                const volatile u8 *tpayload;
                u32 seq2, ack2; u8 fl2; int pl2;
                if (parse_tcp(f, &seq2, &ack2, &fl2, &tpayload, &pl2) &&
                    (fl2 & 0x10) && !(fl2 & 0x02) && ack2 == sisn + 1 &&
                    (((u16)f[36] << 8) | f[37]) == 8081) {
                    ok = 1;
                }
                virtio_net_rx_done();
                if (ok) break;
            }
        }
    }

    /* DNS client: resolve "example.com" via SLIRP DNS (10.0.2.3). */
    {
        volatile u8 *pkt = virtio_net_tx_buffer();
        int i;
        for (i = 0; i < 10; i++) pkt[i] = 0x00;
        build_dns_frame(pkt + 10, gw_mac, offered_ip);
        virtio_net_tx_send(10 + 14 + 20 + 8 + 29);
    }
    {
        int found = 0;
        for (;;) {
            const volatile u8 *f = virtio_net_rx();
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
            virtio_net_rx_done();
            if (found) break;
        }
    }

    schild_sel4_debug_putchar('[');
    schild_sel4_debug_putchar('i');
    schild_sel4_debug_putchar('r');
    schild_sel4_debug_putchar('q');
    schild_sel4_debug_putchar(']');
    schild_sel4_debug_putchar(' ');
    put_dec((u8)virtio_net_irq_count());
    schild_sel4_debug_putchar('\n');

    return 7;
}

extern int schild_spawn_child(void);
extern u64 schild_child_wait(void);

/* Child-domain round-trip: spawn a child with its own CSpace, wait for it to
 * signal its badged result notification, and return the badge (42 on success,
 * 0 on spawn failure). */
u64 schild_child_test(void)
{
    if (!schild_spawn_child()) return 0;
    {
        u64 badge = schild_child_wait();
        schild_sel4_debug_putchar('[');
        schild_sel4_debug_putchar('c');
        schild_sel4_debug_putchar('h');
        schild_sel4_debug_putchar('i');
        schild_sel4_debug_putchar('l');
        schild_sel4_debug_putchar('d');
        schild_sel4_debug_putchar(']');
        schild_sel4_debug_putchar(' ');
        put_dec((u8)badge);
        schild_sel4_debug_putchar('\n');
        return badge;
    }
}
