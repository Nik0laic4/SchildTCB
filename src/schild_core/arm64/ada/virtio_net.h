/* Copyright (C) 2026 Alexander Irganov
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Schild TCB -- virtio-net driver public API (AArch64, QEMU -M virt).
 *
 * The driver owns the virtio-mmio device, the split virtqueues (RX pool +
 * rotating TX) and the IRQ path (a waiter TCB that blocks on the IRQ
 * notification and forwards it to the caller via seL4_Wait).  The protocol
 * stack above it only sees "send a frame / receive a frame".
 */
#ifndef VIRTIO_NET_H
#define VIRTIO_NET_H

typedef unsigned long long u64;
typedef unsigned int       u32;
typedef unsigned short     u16;
typedef unsigned char      u8;

/* Bring up the device, queues and IRQ path.  Returns 1 on success. */
int virtio_net_init(void);

/* TX: return the buffer for the next frame (10-byte virtio_net_hdr + frame). */
volatile u8 *virtio_net_tx_buffer(void);

/* TX: submit the current buffer (len bytes incl. hdr) and wait for the device
 * to consume it. */
void virtio_net_tx_send(u32 len);

/* RX: block until a frame arrives; return a pointer to the Ethernet frame
 * (past the 10-byte virtio_net_hdr). */
const volatile u8 *virtio_net_rx(void);

/* RX: recycle the current frame's buffer back to the device. */
void virtio_net_rx_done(void);

/* Number of IRQs delivered through the seL4 notification so far. */
u32 virtio_net_irq_count(void);

#endif /* VIRTIO_NET_H */
