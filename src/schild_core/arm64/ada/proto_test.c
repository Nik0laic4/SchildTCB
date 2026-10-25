/* Copyright (C) 2026 Alexander Irganov
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Schild TCB -- host-side unit test for the pure protocol logic in net_test.c.
 *
 * net_test.c is freestanding (built for aarch64 bare metal), but its frame
 * builders/parsers (checksum, ARP, IPv4, ICMP, DHCP, UDP, TCP, DNS) are pure
 * buffer-in/buffer-out functions with no seL4 dependency.  We #include the file
 * here, stub the seL4/driver symbols it only uses in the orchestration path,
 * exercise the pure functions against known-good inputs, and measure coverage
 * with gcov (--coverage).  This gives statement/branch coverage of the protocol
 * stack without needing QEMU.
 */
#include <stdio.h>
#include <string.h>

/* ---- stubs for the externs net_test.c references (unused by the pure fns) -- */
void schild_sel4_debug_putchar(char c) { (void)c; }
int  virtio_net_init(void) { return 0; }
int  virtio_net_init_device(void) { return 0; }
volatile unsigned char *virtio_net_tx_buffer(void) { return 0; }
void virtio_net_tx_send(unsigned int len) { (void)len; }
const volatile unsigned char *virtio_net_rx(void) { return 0; }
void virtio_net_rx_done(void) { }
unsigned int virtio_net_irq_count(void) { return 0; }
int schild_spawn_child(void) { return 0; }
unsigned long long schild_child_wait(void) { return 0; }

#include "net_test.c"

static int failures = 0;
#define CHECK(cond) \
    do { if (!(cond)) { printf("  FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); failures++; } } while (0)

static void put_frame(int size, unsigned char *dst, const unsigned char *src)
{
    memcpy(dst, src, (size_t)size);
}

static int test_checksum(void)
{
    volatile unsigned char p[20];
    static const unsigned char src[4] = { 10, 0, 2, 15 };
    static const unsigned char dst[4] = { 10, 0, 2, 2 };
    build_ipv4(p, 20, 1 /* ICMP */, src, dst);
    /* A correct header has a checksum such that csum16(header) == 0. */
    CHECK(csum16(p, 20) == 0);
    CHECK(p[0] == 0x45);
    CHECK(p[9] == 1);
    return 0;
}

static int test_arp(void)
{
    volatile unsigned char pkt[42];
    unsigned char gw[6];
    unsigned char reply[42];

    build_arp_request(pkt);
    CHECK(pkt[12] == 0x08 && pkt[13] == 0x06);        /* EtherType ARP */
    CHECK(pkt[20] == 0x00 && pkt[21] == 0x01);        /* op = request */
    CHECK(pkt[28] == 10 && pkt[31] == 15);            /* sender IP 10.0.2.15 */
    CHECK(pkt[38] == 10 && pkt[41] == 2);             /* target IP 10.0.2.2 */

    /* Craft an ARP reply from 52:54:00:12:34:99 (10.0.2.2). */
    memset(reply, 0xff, 6);                           /* dst broadcast */
    reply[6] = 0x52; reply[7] = 0x54; reply[8] = 0x00;
    reply[9] = 0x12; reply[10] = 0x34; reply[11] = 0x99; /* src */
    reply[12] = 0x08; reply[13] = 0x06;               /* EtherType ARP */
    reply[14] = 0x00; reply[15] = 0x01;               /* htype */
    reply[16] = 0x08; reply[17] = 0x00;               /* ptype IPv4 */
    reply[18] = 0x06; reply[19] = 0x04;               /* hlen/plen */
    reply[20] = 0x00; reply[21] = 0x02;               /* op = reply */
    reply[22] = 0x52; reply[23] = 0x54; reply[24] = 0x00;
    reply[25] = 0x12; reply[26] = 0x34; reply[27] = 0x99; /* sender MAC */
    reply[28] = 10; reply[29] = 0; reply[30] = 2; reply[31] = 2; /* sender IP */
    reply[32] = 0x52; reply[33] = 0x54; reply[34] = 0x00;
    reply[35] = 0x12; reply[36] = 0x34; reply[37] = 0x56; /* target MAC */
    reply[38] = 10; reply[39] = 0; reply[40] = 2; reply[41] = 15; /* target IP */

    CHECK(parse_arp_reply(reply, gw) == 1);
    CHECK(gw[0] == 0x52 && gw[5] == 0x99);
    return 0;
}

static int test_dns(void)
{
    volatile unsigned char pkt[128];
    unsigned char ip[4];
    static const unsigned char mac[6] = { 0x52, 0x54, 0x00, 0x12, 0x34, 0x99 };
    static const unsigned char src_ip[4] = { 10, 0, 2, 15 };

    build_dns_frame(pkt, mac, src_ip);
    CHECK(pkt[36] == 0x00 && pkt[37] == 53);          /* UDP dport 53 */

    /* Craft a minimal DNS reply programmatically (ID 0x1234, A = 1.2.3.4). */
    memset((void *)pkt, 0, 128);
    pkt[12] = 0x08; pkt[13] = 0x00;                   /* EtherType IPv4 */
    pkt[23] = 17;                                     /* proto UDP */
    pkt[34] = 0x00; pkt[35] = 53;                     /* UDP sport 53 */
    pkt[38] = 0x00; pkt[39] = 53;                     /* UDP len = 8 + 45 */
    pkt[42] = 0x12; pkt[43] = 0x34;                   /* DNS ID */
    pkt[44] = 0x81; pkt[45] = 0x80;                   /* QR|RD|RA */
    pkt[48] = 0x00; pkt[49] = 0x01;                   /* QDCOUNT = 1 */
    pkt[50] = 0x00; pkt[51] = 0x01;                   /* ANCOUNT = 1 */
    pkt[54] = 7; memcpy((void *)(pkt + 55), "example", 7);
    pkt[62] = 3; memcpy((void *)(pkt + 63), "com", 3);
    pkt[66] = 0;                                      /* QNAME root */
    pkt[67] = 0x00; pkt[68] = 0x01;                   /* QTYPE A */
    pkt[69] = 0x00; pkt[70] = 0x01;                   /* QCLASS IN */
    pkt[71] = 0xc0; pkt[72] = 0x0c;                   /* answer name ptr */
    pkt[73] = 0x00; pkt[74] = 0x01;                   /* TYPE A */
    pkt[75] = 0x00; pkt[76] = 0x01;                   /* CLASS IN */
    pkt[77] = 0x00; pkt[78] = 0x00; pkt[79] = 0x01; pkt[80] = 0x2c; /* TTL */
    pkt[81] = 0x00; pkt[82] = 0x04;                   /* RDLENGTH 4 */
    pkt[83] = 1; pkt[84] = 2; pkt[85] = 3; pkt[86] = 4; /* A 1.2.3.4 */

    CHECK(parse_dns_reply(pkt, ip) == 1);
    CHECK(ip[0] == 1 && ip[1] == 2 && ip[2] == 3 && ip[3] == 4);
    return 0;
}

static int test_tcp(void)
{
    volatile unsigned char pkt[128];
    const volatile unsigned char *payload;
    u32 seq, ack; u8 fl; int pl;
    static const unsigned char dst_mac[6] = { 0x52, 0x54, 0x00, 0x12, 0x34, 0x99 };
    static const unsigned char src_ip[4] = { 10, 0, 2, 15 };
    static const unsigned char dst_ip[4] = { 10, 0, 2, 2 };

    build_tcp_frame(pkt, dst_mac, src_ip, dst_ip,
                    12345, 8080, 0x12345678u, 0, 0x02 /* SYN */, 0, 0);
    /* TCP header at 14 + 20 = 34; sport [34..35], dport [36..37]. */
    CHECK(pkt[34] == 0x30 && pkt[35] == 0x39);        /* sport 12345 */
    CHECK(pkt[36] == 0x1f && pkt[37] == 0x90);        /* dport 8080 */

    CHECK(parse_tcp(pkt, &seq, &ack, &fl, &payload, &pl) == 1);
    CHECK(seq == 0x12345678u && fl == 0x02 && pl == 0);
    return 0;
}

static int test_dhcp(void)
{
    volatile unsigned char pkt[400];
    unsigned char ip[4];

    build_dhcp_frame(pkt);
    CHECK(pkt[34] == 0x00 && pkt[35] == 68);          /* UDP sport 68 */
    CHECK(pkt[36] == 0x00 && pkt[37] == 67);          /* UDP dport 67 */

    /* Craft a minimal DHCP OFFER: BOOTREPLY + yiaddr 10.0.2.15. */
    memset((void *)pkt, 0, 400);
    pkt[12] = 0x08; pkt[13] = 0x00;                   /* EtherType IPv4 */
    pkt[23] = 17;                                     /* proto UDP */
    pkt[36] = 0x00; pkt[37] = 68;                     /* UDP dport 68 */
    pkt[42] = 0x02;                                   /* DHCP op = BOOTREPLY */
    pkt[58] = 10; pkt[59] = 0; pkt[60] = 2; pkt[61] = 15; /* yiaddr 10.0.2.15 */

    CHECK(parse_dhcp_offer(pkt, ip) == 1);
    CHECK(ip[0] == 10 && ip[3] == 15);
    return 0;
}

int main(void)
{
    test_checksum();
    test_arp();
    test_dns();
    test_tcp();
    test_dhcp();
    if (failures == 0) {
        printf("proto_test: OK\n");
        return 0;
    }
    printf("proto_test: %d failure(s)\n", failures);
    return 1;
}

