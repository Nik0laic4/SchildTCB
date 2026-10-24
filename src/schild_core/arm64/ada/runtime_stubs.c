/* Copyright (C) 2026 Alexander Irganov
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * GNAT Zero-Footprint-Profile runtime stubs for AArch64 bare metal.
 *
 * The bare_runtime is source-only and deliberately omits the exception/unwind
 * machinery (gnat.adc: No_Exception_Propagation, No_Secondary_Stack, ...).
 * GNAT's generated code still references a handful of runtime symbols that the
 * ZFP sources intentionally do not provide:
 *
 *   - __gnat_rcheck_*        runtime checks (range / overflow / index / ...)
 *   - __gnat_last_chance_handler
 *   - memcpy / memset / memcmp   (bare-metal libc replacements)
 *   - _Unwind_Resume, __gnat_*_handler_*, __gnat_unhandled_exception
 *
 * These stubs satisfy the linker.  A runtime check is a *programming error*:
 * in a validated build it must never fire, so on the rare failure we report it
 * on the PL011 console and halt in a low-power wait loop (there is no OS to
 * return to).  This mirrors the x86_64 seL4 shim (tools/sel4/src/message_info.c)
 * but targets the emulated PL011 of qemu-system-aarch64 "-M virt".
 */

/* ---- PL011 UART (qemu "-M virt": data @ 0x0900_0000, flags @ 0x0900_0018) ---- */
static void uart_putc(char c)
{
    volatile unsigned int *fr = (volatile unsigned int *)0x09000018u;
    volatile unsigned int *dr = (volatile unsigned int *)0x09000000u;
    while (*fr & (1u << 5)) {   /* wait while transmit FIFO is full (TXFF) */
    }
    *dr = (unsigned int)(unsigned char)c;
}

static void uart_puts(const char *s)
{
    for (; *s; s++) {
        uart_putc(*s);
    }
}

static void uart_putdec(int v)
{
    char buf[16];
    int i = 0;
    if (v <= 0) { uart_putc('0'); return; }
    while (v > 0 && i < (int)sizeof(buf)) {
        buf[i++] = (char)('0' + (v % 10));
        v /= 10;
    }
    while (i > 0) {
        uart_putc((char)buf[--i]);
    }
}

/* Fatal runtime-check handler: report the failing check + source location, then
 * halt the core.  No OS is present, so there is nothing to unwind to. */
static void __attribute__((noreturn)) rt_check_fail(const char *kind,
                                                    const char *file, int line)
{
    uart_puts("RUNTIME CHECK FAILED: ");
    uart_puts(kind);
    uart_puts(" @ ");
    uart_puts(file ? file : "?");
    uart_puts(":");
    uart_putdec(line);
    uart_puts("\r\n");
    for (;;) {
        __asm__ volatile("wfi");
    }
}

/* ---- GNAT runtime check stubs ---- */
void __gnat_rcheck_CE_Access_Check(const char *f, int l)   { rt_check_fail("Access_Check", f, l); }
void __gnat_rcheck_CE_Index_Check(const char *f, int l)    { rt_check_fail("Index_Check", f, l); }
void __gnat_rcheck_CE_Range_Check(const char *f, int l)    { rt_check_fail("Range_Check", f, l); }
void __gnat_rcheck_CE_Overflow_Check(const char *f, int l) { rt_check_fail("Overflow_Check", f, l); }
void __gnat_rcheck_CE_Invalid_Data(const char *f, int l)   { rt_check_fail("Invalid_Data", f, l); }
void __gnat_rcheck_CE_Length_Check(const char *f, int l)   { rt_check_fail("Length_Check", f, l); }
void __gnat_rcheck_CE_Divide_By_Zero(const char *f, int l) { rt_check_fail("Divide_By_Zero", f, l); }
void __gnat_rcheck_CE_Null_Access_Parameter(const char *f, int l) { rt_check_fail("Null_Access_Parameter", f, l); }
void __gnat_rcheck_CE_Discriminant_Check(const char *f, int l)    { rt_check_fail("Discriminant_Check", f, l); }
void __gnat_rcheck_CE_Explicit_Raise(const char *f, int l)        { rt_check_fail("Explicit_Raise", f, l); }
void __gnat_rcheck_CE_Null_Exception_Id(const char *f, int l)     { rt_check_fail("Null_Exception_Id", f, l); }
void __gnat_rcheck_CE_Null_Not_Allowed(const char *f, int l)      { rt_check_fail("Null_Not_Allowed", f, l); }
void __gnat_rcheck_PE_Stream_Operation(const char *f, int l)      { rt_check_fail("Stream_Operation", f, l); }
void __gnat_last_chance_handler(const char *s, int l)             { rt_check_fail("last_chance", s, l); }

/* ---- Bare-metal libc replacements ---- */
int memcmp(const void *a, const void *b, unsigned long n)
{
    const unsigned char *pa = (const unsigned char *)a;
    const unsigned char *pb = (const unsigned char *)b;
    for (unsigned long i = 0; i < n; i++) {
        if (pa[i] != pb[i]) return pa[i] - pb[i];
    }
    return 0;
}

void *memcpy(void *d, const void *s, unsigned long n)
{
    unsigned char *pd = (unsigned char *)d;
    const unsigned char *ps = (const unsigned char *)s;
    for (unsigned long i = 0; i < n; i++) pd[i] = ps[i];
    return d;
}

void *memset(void *d, int c, unsigned long n)
{
    unsigned char *pd = (unsigned char *)d;
    for (unsigned long i = 0; i < n; i++) pd[i] = (unsigned char)c;
    return d;
}

/* ---- Exception/unwind stubs (ZFP: no propagation, no unwinding) ---- */
void _Unwind_Resume(void)              { for (;;) __asm__ volatile("wfi"); }
void __gnat_begin_handler_v1(void)     { for (;;) __asm__ volatile("wfi"); }
void __gnat_end_handler_v1(void)       { for (;;) __asm__ volatile("wfi"); }
void __gnat_unhandled_exception(void)  { for (;;) __asm__ volatile("wfi"); }
void *__gnat_others_value;             /* referenced by .gcc_except_table */
