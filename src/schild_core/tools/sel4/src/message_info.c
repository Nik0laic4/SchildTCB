/*
 * Copyright (C) 2026 Alexander Irganov
 * SPDX-License-Identifier: GPL-2.0-only
 */

/* Return BootInfo pointer saved by rt_start.S from seL4's RDI register.
 * Uses the global rt_bootinfo_vptr symbol (set in assembly before Ada code runs).
 * This replaces the hardcoded 0x404000 — works regardless of root task ELF size.
 */
#include "ipc_limits.h"

/* The seL4 bootinfo pointer must be a full 64-bit address. */
_Static_assert(sizeof(void*) == 8, "bootinfo pointer must be 64-bit");

extern unsigned long rt_bootinfo_vptr;
void *schild_get_bootinfo(void) { return (void*)rt_bootinfo_vptr; }
unsigned long long schild_get_bootinfo_frame(void) { return (unsigned long long)rt_bootinfo_vptr; }

/* Value copy of the seL4 BootInfo frame into a caller-provided buffer.
 * Lets the Ada root task read BootInfo as a VALUE (SPARK-provable) instead of
 * dereferencing the opaque C pointer.  nbytes is BootInfo'Size/8 passed from Ada. */
void schild_get_bootinfo_copy(void *dest, unsigned long long nbytes) {
    unsigned char *d = (unsigned char *)dest;
    const unsigned char *s = (const unsigned char *)rt_bootinfo_vptr;
    unsigned long long i;
    for (i = 0; i < nbytes; i++) d[i] = s[i];
}

/* ─── GNAT runtime check stubs — safe fallback for Ring 3 user space ─── */
/* These are linked when -gnatp is NOT used.  They trap into an infinite   */
/* pause loop to prevent silent crashes in production.                     */

extern void schild_pause(void);
extern void schild_sel4_debug_putchar(unsigned int c);

static void rt_puts(const char *s) {
    for (; *s; s++) schild_sel4_debug_putchar((unsigned int)*s);
}

static void rt_putdec(int v) {
    char buf[16];
    int i = 0;
    if (v <= 0) { schild_sel4_debug_putchar('0'); return; }
    while (v > 0 && i < (int)sizeof(buf)) {
        buf[i++] = (char)('0' + (v % 10));
        v /= 10;
    }
    while (i > 0) schild_sel4_debug_putchar((unsigned int)buf[--i]);
}

/* Fatal runtime-check handler: report the failing check and source location
 * over UART, then trap in a low-power loop. Full fault-domain isolation and
 * restart is a separate architectural step (see ARCHITECTURE.md). */
static void __attribute__((noreturn)) rt_check_fail(const char *kind,
                                                    const char *file, int line) {
    rt_puts("RUNTIME CHECK FAILED: ");
    rt_puts(kind);
    rt_puts(" @ ");
    rt_puts(file ? file : "?");
    rt_puts(":");
    rt_putdec(line);
    rt_puts("\n");
    for (;;) schild_pause();
}

void __gnat_rcheck_CE_Access_Check  (const char *f, int l) { rt_check_fail("Access_Check", f, l); }
void __gnat_rcheck_CE_Index_Check   (const char *f, int l) { rt_check_fail("Index_Check", f, l); }
void __gnat_rcheck_CE_Range_Check   (const char *f, int l) { rt_check_fail("Range_Check", f, l); }
void __gnat_rcheck_CE_Overflow_Check(const char *f, int l) { rt_check_fail("Overflow_Check", f, l); }
void __gnat_rcheck_CE_Invalid_Data  (const char *f, int l) { rt_check_fail("Invalid_Data", f, l); }
void __gnat_rcheck_CE_Length_Check  (const char *f, int l) { rt_check_fail("Length_Check", f, l); }
void __gnat_rcheck_CE_Divide_By_Zero(const char *f, int l) { rt_check_fail("Divide_By_Zero", f, l); }
void __gnat_rcheck_CE_Null_Access_Parameter(const char *f, int l) { rt_check_fail("Null_Access_Parameter", f, l); }
void __gnat_rcheck_CE_Discriminant_Check(const char *f, int l)  { rt_check_fail("Discriminant_Check", f, l); }
void __gnat_rcheck_CE_Explicit_Raise(const char *f, int l)     { rt_check_fail("Explicit_Raise", f, l); }
void __gnat_rcheck_CE_Null_Exception_Id(const char *f, int l)  { rt_check_fail("Null_Exception_Id", f, l); }
void __gnat_rcheck_CE_Null_Not_Allowed(const char *f, int l)   { rt_check_fail("Null_Not_Allowed", f, l); }
void __gnat_rcheck_PE_Stream_Operation(const char *f, int l)   { rt_check_fail("Stream_Operation", f, l); }
void __gnat_last_chance_handler(const char *s, int l)          { rt_check_fail("last_chance", s, l); }

/* Exception propagation stubs — GNAT ZFP limitation.
 * Full exception handling requires libgcc unwinding which is not
 * available in bare-metal user-space.  Use structural error handling
 * (no exception blocks) in production code.
 */

/* ─── Bare-metal C library stubs ─── */
int memcmp(const void *a, const void *b, unsigned long n) {
    const unsigned char *pa = (const unsigned char *)a;
    const unsigned char *pb = (const unsigned char *)b;
    for (unsigned long i = 0; i < n; i++)
        if (pa[i] != pb[i]) return pa[i] - pb[i];
    return 0;
}
void *memcpy(void *d, const void *s, unsigned long n) {
    unsigned char *pd = (unsigned char *)d;
    const unsigned char *ps = (const unsigned char *)s;
    for (unsigned long i = 0; i < n; i++) pd[i] = ps[i];
    return d;
}
void *memset(void *d, int c, unsigned long n) {
    unsigned char *pd = (unsigned char *)d;
    for (unsigned long i = 0; i < n; i++) pd[i] = (unsigned char)c;
    return d;
}

/* Panic handler for the root-task runtime: halt the faulting thread. Ring 3
 * cannot reset the CPU (`hlt` is privileged and would itself fault); the seL4
 * kernel and the other domains are unaffected by this loop. */
void rt_panic(void) {
    for (;;) __asm__ volatile("pause");
}

void _Unwind_Resume(void)                        { rt_panic(); }
void __gnat_begin_handler_v1(void)               { rt_panic(); }
void __gnat_end_handler_v1(void)                 { rt_panic(); }
void __gnat_unhandled_exception(void)            { rt_panic(); }
void *__gnat_others_value;  /* referenced by .gcc_except_table */
