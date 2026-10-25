#!/usr/bin/env python3
# Copyright (C) 2026 Alexander Irganov
# SPDX-License-Identifier: GPL-2.0-only
#
# Schild TCB -- deterministic host-side network peer for QEMU's `-netdev socket`
# backend.  Replaces SLIRP: it answers the guest's ARP / ICMP / DHCP /
# TCP(HTTP) / DNS requests with fixed addresses and initiates the TCP-server
# handshake, so the whole protocol test is reproducible and offline.
#
# The QEMU socket backend frames each Ethernet frame as:
#   uint32_be(length) || frame[length]
# This peer speaks that framing on a TCP socket.

import socket
import struct
import threading
import time

PEER_MAC = bytes([0x52, 0x54, 0x00, 0x12, 0x34, 0x99])
GUEST_MAC = bytes([0x52, 0x54, 0x00, 0x12, 0x34, 0x56])
GUEST_IP = (10, 0, 2, 15)
GATEWAY_IP = (10, 0, 2, 2)
DNS_IP = (10, 0, 2, 3)

HTTP_RESPONSE = b"HTTP/1.0 200 OK\r\nContent-Length: 13\r\n\r\nSchildTCB-body"
DNS_A = bytes([1, 2, 3, 4])

ETH_IPV4 = 0x0800
ETH_ARP = 0x0806

# The peer's TCP ports: 8080 = HTTP server (guest is the client), 43210 = the
# peer's client port for the guest's TCP server on 8081.
HTTP_PORT = 8080
CLIENT_PORT = 43210
SERVER_PORT = 8081


def _csum(data):
    if len(data) % 2:
        data += b"\x00"
    total = sum(struct.unpack("!%dH" % (len(data) // 2), data))
    while total >> 16:
        total = (total & 0xFFFF) + (total >> 16)
    return (~total) & 0xFFFF


def _ipb(ip):
    return bytes(ip)


def eth_frame(dst, src, ethertype, payload):
    return dst + src + struct.pack("!H", ethertype) + payload


def ipv4(src, dst, proto, payload, ident=0):
    total = 20 + len(payload)
    hdr = struct.pack("!BBHHHBBH4s4s", 0x45, 0, total, ident, 0, 64, proto,
                      0, _ipb(src), _ipb(dst))
    hdr = hdr[:10] + struct.pack("!H", _csum(hdr)) + hdr[12:]
    return hdr + payload


def udp(src, dst, sport, dport, payload):
    seg = struct.pack("!HHHH", sport, dport, 8 + len(payload), 0) + payload
    ph = _ipb(src) + _ipb(dst) + struct.pack("!BBH", 0, 17, 8 + len(payload))
    c = _csum(ph + seg)
    if c == 0:
        c = 0xFFFF
    return seg[:6] + struct.pack("!H", c) + seg[8:]


def tcp(src, dst, sport, dport, seq, ack, flags, payload=b""):
    seg = struct.pack("!HHIIBBHHH", sport, dport, seq, ack, 0x50, flags,
                      8192, 0, 0) + payload
    ph = _ipb(src) + _ipb(dst) + struct.pack("!BBH", 0, 6, len(seg))
    c = _csum(ph + seg)
    return seg[:16] + struct.pack("!H", c) + seg[18:]


def _ip_frame(dst_ip, proto, payload):
    return eth_frame(GUEST_MAC, PEER_MAC, ETH_IPV4,
                     ipv4(GATEWAY_IP, dst_ip, proto, payload))


def _arp_reply(arp):
    # arp = the 28-byte ARP body of the request.
    sha = arp[8:14]    # sender MAC  (guest)
    spa = arp[14:18]   # sender IP   (guest)
    tpa = arp[24:28]   # target IP   (the address being resolved)
    body = struct.pack("!HHBBH", 1, 0x0800, 6, 4, 2) + PEER_MAC + tpa + sha + spa
    return eth_frame(GUEST_MAC, PEER_MAC, ETH_ARP, body)


def _icmp_reply(icmp):
    # icmp = the ICMP message (echo request) after the IPv4 header.
    echo = icmp[4:]    # id + seq + data
    body = bytes([0, 0]) + struct.pack("!H", _csum(bytes([0, 0, 0, 0]) + echo)) + echo
    return _ip_frame(GUEST_IP, 1, body)


def _dhcp_offer(dhcp):
    xid = dhcp[4:8]
    chaddr = dhcp[28:34]
    msg = bytearray(300)
    msg[0] = 0x02          # BOOTREPLY
    msg[1] = 0x01          # Ethernet
    msg[2] = 0x06
    msg[4:8] = xid
    msg[10] = 0x80         # broadcast flag
    msg[16:20] = _ipb(GUEST_IP)   # yiaddr
    msg[28:34] = chaddr
    msg[236:240] = bytes([0x63, 0x82, 0x53, 0x63])  # magic cookie
    o = 240
    msg[o] = 53; msg[o + 1] = 1; msg[o + 2] = 2; o += 3          # DHCP OFFER
    msg[o] = 1; msg[o + 1] = 4; msg[o + 2:o + 6] = b"\xff\xff\xff\x00"; o += 6
    msg[o] = 3; msg[o + 1] = 4; msg[o + 2:o + 6] = _ipb(GATEWAY_IP); o += 6
    msg[o] = 54; msg[o + 1] = 4; msg[o + 2:o + 6] = _ipb(GATEWAY_IP); o += 6
    msg[o] = 255          # end
    payload = udp(GATEWAY_IP, (255, 255, 255, 255), 67, 68, bytes(msg))
    return eth_frame(GUEST_MAC, PEER_MAC, ETH_IPV4,
                     ipv4(GATEWAY_IP, (255, 255, 255, 255), 17, payload))


def _dns_reply(dns):
    qid = dns[0:2]
    hdr = qid + struct.pack("!HHHHH", 0x8180, 1, 1, 0, 0)
    question = dns[12:]   # echo the QNAME + QTYPE + QCLASS
    answer = struct.pack("!HHHIH", 0xC00C, 1, 1, 300, 4) + DNS_A
    payload = udp(DNS_IP, GUEST_IP, 53, 53000, hdr + question + answer)
    return eth_frame(GUEST_MAC, PEER_MAC, ETH_IPV4, ipv4(DNS_IP, GUEST_IP, 17, payload))


class NetPeer:
    """Host peer for the guest's protocol stack (one connection)."""

    def __init__(self, port):
        self.port = port
        self.http_isn = 0xDEADBEEF
        self.client_isn = 0x12344321
        self.client_handshaken = False

    def serve(self, stop_event):
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        srv.bind(("127.0.0.1", self.port))
        srv.listen(1)
        srv.settimeout(0.5)
        while not stop_event.is_set():
            try:
                conn, _ = srv.accept()
            except socket.timeout:
                continue
            conn.settimeout(0.5)
            self._serve_conn(conn, stop_event)
            conn.close()
            srv.close()
            return
        srv.close()

    def _serve_conn(self, conn, stop_event):
        buf = b""
        while not stop_event.is_set():
            try:
                chunk = conn.recv(4096)
            except socket.timeout:
                continue
            if not chunk:
                return
            buf += chunk
            while len(buf) >= 4:
                length = struct.unpack("!I", buf[:4])[0]
                if len(buf) < 4 + length:
                    break
                self._handle(conn, buf[4:4 + length])
                buf = buf[4 + length:]

    def _send(self, conn, frame):
        conn.sendall(struct.pack("!I", len(frame)) + frame)

    def _handle(self, conn, frame):
        if len(frame) < 14:
            return
        ethertype = struct.unpack("!H", frame[12:14])[0]
        if ethertype == ETH_ARP:
            self._send(conn, _arp_reply(frame[14:]))
            return
        if ethertype != ETH_IPV4 or len(frame) < 34:
            return
        proto = frame[23]
        if proto == 1:      # ICMP echo
            self._send(conn, _icmp_reply(frame[34:]))
        elif proto == 17:   # UDP
            sport, dport = struct.unpack("!HH", frame[34:38])
            if dport == 67:
                self._send(conn, _dhcp_offer(frame[42:]))
            elif dport == 53:
                self._send(conn, _dns_reply(frame[42:]))
        elif proto == 6:    # TCP
            self._handle_tcp(conn, frame)

    def _handle_tcp(self, conn, frame):
        ihl = (frame[14] & 0x0F) * 4
        total = struct.unpack("!H", frame[16:18])[0]
        tcp_start = 14 + ihl
        sport, dport, seq, ack, off_flags = struct.unpack(
            "!HHIIH", frame[tcp_start:tcp_start + 14])
        flags = off_flags & 0x1FF
        doff = (off_flags >> 12) * 4
        plen = total - ihl - doff

        if dport == HTTP_PORT:  # HTTP server: guest is the client
            if flags & 0x02 and not flags & 0x10:  # SYN
                resp = tcp(GATEWAY_IP, GUEST_IP, HTTP_PORT, sport,
                           self.http_isn, seq + 1, 0x12)
                self._send(conn, _ip_frame(GUEST_IP, 6, resp))
            elif flags & 0x10 and plen > 0:        # ACK + HTTP GET
                resp = tcp(GATEWAY_IP, GUEST_IP, HTTP_PORT, sport,
                           self.http_isn + 1, seq + plen, 0x18, HTTP_RESPONSE)
                self._send(conn, _ip_frame(GUEST_IP, 6, resp))
                threading.Thread(target=self._tcp_client, args=(conn,),
                                 daemon=True).start()
        elif dport == CLIENT_PORT and (flags & 0x12) == 0x12 and not self.client_handshaken:
            # SYN-ACK from the guest's TCP server: complete the handshake with
            # ack = server_seq + 1 (the server's next expected sequence).
            resp = tcp(GATEWAY_IP, GUEST_IP, CLIENT_PORT, SERVER_PORT,
                       self.client_isn + 1, seq + 1, 0x10)
            self._send(conn, _ip_frame(GUEST_IP, 6, resp))
            self.client_handshaken = True

    def _tcp_client(self, conn):
        """Initiate the TCP-server handshake once the guest has reached the
        server stage (it does so right after the HTTP response)."""
        time.sleep(0.3)
        syn = tcp(GATEWAY_IP, GUEST_IP, CLIENT_PORT, SERVER_PORT,
                  self.client_isn, 0, 0x02)
        self._send(conn, _ip_frame(GUEST_IP, 6, syn))


def run(port, stop_event):
    NetPeer(port).serve(stop_event)

