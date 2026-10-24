/*
 * Copyright (C) 2026 Alexander Irganov
 * SPDX-License-Identifier: GPL-2.0-only
 */

/*
 *
 * PRIVATE OVERLAY (private/root_task) — Stage 9.2.
 * Production Ring 3 runtime for the NetServer. Overlaid by build_rt.sh when
 * SCHILD_PROFILE=private. Same scaffolding as the public file, except the
 * audit bridge below is the production renderer: schild_debug_render forwards
 * to the Ada export schild_audit_render, which performs the honest Read_Event
 * loop over the (overlaid) Schild_Audit_Logger and fills the buffer with real
 * log lines. In the public profile the logger is a stub ("0 buffered").
 *   - UART output via the seL4 DebugPutChar syscall (no port I/O in Ring 3).
 *   - DMA physical-address translation via schild_dma_phys (virtual + offset).
 *   - No-op stubs for Ring 0-only operations (wbinvd, map_mmio_2mb, IOAPIC).
 */

typedef unsigned long long u64;
typedef unsigned int u32;

extern void schild_sel4_debug_putchar(u32 c);

/* UART output via seL4 DebugPutChar (kernel debug channel). */
void schild_uart_putln(const char *msg, int len) {
    int i;
    for (i = 0; i < len; i++) schild_sel4_debug_putchar((unsigned char)msg[i]);
    schild_sel4_debug_putchar('\r');
    schild_sel4_debug_putchar('\n');
}

void schild_uart_puts(const char *msg, int len) {
    int i;
    for (i = 0; i < len; i++) schild_sel4_debug_putchar((unsigned char)msg[i]);
}

/* Address -> u64 (virtual, used by the CPU side). */
unsigned long long schild_ptr_to_u64(void *ptr) {
    return (unsigned long long)(unsigned long)ptr;
}

/* DMA physical-address translation: virtual + (phys_base - image_vbase). */
static unsigned long long dma_offset = 0;
void schild_set_dma_offset(unsigned long long off) { dma_offset = off; }
unsigned long long schild_dma_phys(void *ptr) {
    return (unsigned long long)(unsigned long)ptr + dma_offset;
}

/* CLFLUSH is unprivileged — keep it real for DMA coherence. */
void schild_clflush(void *addr) {
    __asm__ volatile("clflush (%0)" : : "r"(addr) : "memory");
}

/* One-time warning print: surfacing (not masking) a Ring 0-only helper that was
 * incorrectly invoked from Ring 3. */
static void put_str(const char *s) {
    for (; *s; s++) schild_sel4_debug_putchar((unsigned char)*s);
}
static void warn_once(const char *msg) {
    put_str(msg);
    schild_sel4_debug_putchar('\r');
    schild_sel4_debug_putchar('\n');
}

/* Ring 0-only helpers — no-ops in Ring 3, by design:
 *   - wbinvd is a privileged instruction (Ring 3 cannot execute it); the driver
 *     must use clflush instead for DMA coherence.
 *   - MMIO is mapped in advance by the Root Task via X86PageMap.
 *   - IOAPIC/IRQ routing is Ring 0 only (Ring 3 uses polling).
 * A call here indicates a programming error, so each stub warns instead of
 * silently ignoring it. */
void schild_wbinvd(void) {
    static int warned = 0;
    if (!warned) { warned = 1; warn_once("[NET-RT] WARN: wbinvd no-op in Ring 3 (use clflush)"); }
}
void schild_map_mmio_2mb(unsigned long long phys) {
    (void)phys;
    static int warned = 0;
    if (!warned) { warned = 1; warn_once("[NET-RT] WARN: map_mmio_2mb no-op in Ring 3 (pre-mapped)"); }
}
void schild_e1000e_set_mmio(unsigned long long mmio) {
    (void)mmio;
    static int warned = 0;
    if (!warned) { warned = 1; warn_once("[NET-RT] WARN: e1000e_set_mmio no-op in Ring 3"); }
}
void schild_ioapic_unmask_pin(unsigned int pin, unsigned int vec) {
    (void)pin; (void)vec;
    static int warned = 0;
    if (!warned) { warned = 1; warn_once("[NET-RT] WARN: ioapic_unmask_pin no-op in Ring 3 (polling)"); }
}

/* NVMe ACQ helpers — stubs (no NVMe storage in the Ring 3 network test). */
static unsigned long long nvme_ext_acq = 0;
void schild_nvme_set_ext_acq(unsigned long long addr) { nvme_ext_acq = addr; }
int schild_nvme_poll_acq(void) { return 0; }
unsigned char schild_nvme_read_acq(unsigned int off) {
    (void)off; return 0;
}

/* ─── Stage 8.4: shared DMA frame (large-frame transfer, no MR limit) ──────
 * A 4KB frame is retyped by the Root Task and mapped at 0x520000 in BOTH the
 * root VSpace and the NetServer VSpace. Large frames (> 960 B, the seL4 MR
 * limit) are exchanged through this frame instead of message registers.
 * These helpers are linked into root_task.elf, so both the Root Task and the
 * NetServer (separate processes sharing the same image) can call them. */
#define SHARED_FRAME_VADDR 0x520000

void schild_shared_copy_from(void *dst, unsigned int len) {
    unsigned char *s = (unsigned char *)(unsigned long)SHARED_FRAME_VADDR;
    unsigned char *d = (unsigned char *)dst;
    unsigned int i;
    for (i = 0; i < len; i++) d[i] = s[i];
}

void schild_shared_copy_to(const void *src, unsigned int len) {
    const unsigned char *s = (const unsigned char *)src;
    unsigned char *d = (unsigned char *)(unsigned long)SHARED_FRAME_VADDR;
    unsigned int i;
    for (i = 0; i < len; i++) d[i] = s[i];
}

/* ─── Stage 9: network debug bridge (real) ──────────────────────────────
 * The audit-log renderer is implemented in Ada (Schild_Audit_Logger's
 * Audit_Event type is an Ada record), exported as schild_audit_render.
 * This C bridge is what the core-tree HTTP server imports; it forwards to
 * the Ada renderer so the log text lands in the caller's buffer. */
extern void schild_audit_render(void *buffer, int max_len, int *actual_len);

void schild_debug_render(void *buffer, int max_len, int *actual_len) {
    schild_audit_render(buffer, max_len, actual_len);
}

