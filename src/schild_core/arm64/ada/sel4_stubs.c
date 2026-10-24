/* Copyright (C) 2026 Alexander Irganov
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * seL4 AArch64 root-task shim: DebugPutChar syscall + GNAT runtime stubs.
 *
 * The Ada root task talks to seL4 through a single debug syscall
 * (seL4_SysDebugPutChar, syscall number -9): x0 = character, x7 = -9, "svc #0".
 * The bare_runtime ZFP sources do not provide the exception/unwind machinery, so
 * this shim also supplies the __gnat_rcheck_* / __gnat_last_chance_handler /
 * memcpy / memset / memcmp / _Unwind_* symbols that GNAT's generated code
 * references but the ZFP runtime intentionally omits (see gnat.adc).
 *
 * This mirrors the x86_64 shim (tools/sel4/src/message_info.c) for AArch64.
 */

/* ---- seL4 DebugPutChar syscall (syscall id -9) ---- */
void schild_sel4_debug_putchar(char c)
{
    register long x0 asm("x0") = (long)(unsigned char)c;
    register long x7 asm("x7") = -9;
    __asm__ volatile("svc #0" : : "r"(x0), "r"(x7) : "memory");
}

/* Low-power pause for a halted (faulted) root task. */
void schild_pause(void)
{
    __asm__ volatile("wfe");
}

/* ---- Fatal runtime-check handler: report then halt ---- */
static void rt_puts(const char *s)
{
    for (; *s; s++) {
        schild_sel4_debug_putchar(*s);
    }
}

static void rt_putdec(int v)
{
    char buf[16];
    int i = 0;
    if (v <= 0) { schild_sel4_debug_putchar('0'); return; }
    while (v > 0 && i < (int)sizeof(buf)) {
        buf[i++] = (char)('0' + (v % 10));
        v /= 10;
    }
    while (i > 0) {
        schild_sel4_debug_putchar((char)buf[--i]);
    }
}

static void __attribute__((noreturn)) rt_check_fail(const char *kind,
                                                    const char *file, int line)
{
    rt_puts("RUNTIME CHECK FAILED: ");
    rt_puts(kind);
    rt_puts(" @ ");
    rt_puts(file ? file : "?");
    rt_puts(":");
    rt_putdec(line);
    rt_puts("\n");
    for (;;) {
        schild_pause();
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
void _Unwind_Resume(void)             { for (;;) schild_pause(); }
void __gnat_begin_handler_v1(void)    { for (;;) schild_pause(); }
void __gnat_end_handler_v1(void)      { for (;;) schild_pause(); }
void __gnat_unhandled_exception(void) { for (;;) schild_pause(); }
void *__gnat_others_value;            /* referenced by .gcc_except_table */
