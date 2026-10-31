/*
 * Copyright (C) 2026 Alexander Irganov
 * SPDX-License-Identifier: GPL-2.0-only
 */

/*
 * Schild TCB Stage 8.1C — Ring 3 runtime for the e1000e driver + network
 * stack (NetServer).  Provides the C helpers the Ada driver imports, adapted
 * for the seL4 user-space context:
 *   - UART output via the seL4 DebugPutChar syscall (no port I/O in Ring 3).
 *   - DMA physical-address translation via schild_dma_phys (virtual + offset).
 *   - No-op stubs for Ring 0-only operations (wbinvd, map_mmio_2mb, IOAPIC).
 *
 * NOTE (private overlay): kept byte-identical to the public scaffold
 * (tools/sel4/src/schild_net_runtime.c). The "production renderer" difference
 * lives in the overlaid Ada Schild_Audit_Logger (schild_audit_render), not in
 * this C file — schild_debug_render only forwards. Do NOT let this file drift
 * from the public one.
 */

typedef unsigned long long u64;
typedef unsigned int u32;

/* Boot-log capture ring. Mirrors runtime_stubs.c so the root-task build can
 * link schild_nvme.adb (Flush_Log_To_Nvme). In the root task the ring is not
 * actively filled (logging goes via DebugPutChar), so the flush is a no-op. */
#define SCHILD_LOG_SIZE 8192
char schild_log_buf[SCHILD_LOG_SIZE];
unsigned int schild_log_len = 0;

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

/* Ring 3 MMIO read/write helpers (W2: ECAM config-space access). */
unsigned long long schild_mmio_read32(unsigned long long addr) {
    return (unsigned long long)(*(volatile unsigned int *)(unsigned long)addr);
}
void schild_mmio_write32(unsigned long long addr, unsigned long long val) {
    *(volatile unsigned int *)(unsigned long)addr = (unsigned int)val;
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

/* W7: NVMe MMIO base vaddr (0 = storage disabled). Set by the Root Task after
 * mapping the NVMe BAR0 into the NetServer VSpace; read by schild_nvme_init. */
static unsigned long long nvme_mmio_base = 0;
void schild_nvme_set_mmio(unsigned long long base) { nvme_mmio_base = base; }
unsigned long long schild_nvme_get_mmio(void) { return nvme_mmio_base; }

/* ─── Stage 8.4: shared DMA frame (large-frame transfer, no MR limit) ──────
 * A 4KB frame is retyped by the Root Task and mapped at 0x520000 in BOTH the
 * root VSpace and the NetServer VSpace. Large frames (> 960 B, the seL4 MR
 * limit) are exchanged through this frame instead of message registers.
 * These helpers are linked into root_task.elf, so both the Root Task and the
 * NetServer (separate processes sharing the same image) can call them. */
#define SHARED_FRAME_VADDR 0x52A000

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

/* ─── Standalone-kernel IRQ symbols (link-time stubs for the seL4 build) ──
 * schild_net_stack.adb imports these for the bare-metal IRQ-driven RX loop
 * (Run_Loop). The seL4 NetServer does NOT call Run_Loop — it drives RX via its
 * own seL4 IRQ notification + Poll_And_Process — so these are never invoked
 * here; they only satisfy the linker. */
volatile unsigned int e1000e_rx_pending = 0;
volatile unsigned int e1000e_irq_count = 0;
void schild_hlt(void) { __asm__ volatile("pause"); }
void schild_sti(void) { }
void schild_cli(void) { }
void schild_log_hex32(unsigned int v) { (void)v; }

