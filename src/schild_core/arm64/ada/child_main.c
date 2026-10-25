/* Copyright (C) 2026 Alexander Irganov
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Schild TCB -- child process (separate VSpace demo).
 *
 * This is the first true process in the ARM64 port: a self-contained ELF that
 * runs in its OWN VSpace and CSpace.  It proves both by printing a marker over
 * the seL4 debug console (any thread may use seL4_SysDebugPutChar) and then
 * signalling the badged result notification in its CSpace slot 0.  The root
 * task observes badge 42 and reports the child's result.
 *
 * No runtime library is linked: the two syscalls below are raw "svc #0" shims.
 */
typedef unsigned long long u64;

static inline void child_debug_putchar(char c)
{
    register long x0 asm("x0") = (long)(unsigned char)c;
    register long x7 asm("x7") = -9;   /* seL4_SysDebugPutChar */
    __asm__ volatile("svc #0" : : "r"(x0), "r"(x7) : "memory");
}

static void child_puts(const char *s)
{
    for (; *s; s++) {
        child_debug_putchar(*s);
    }
}

static inline void child_signal(u64 dest)
{
    register u64 x0 asm("x0") = dest;
    register u64 x1 asm("x1") = 0;     /* empty message info */
    register u64 x7 asm("x7") = -3;    /* seL4_SysSend */
    __asm__ volatile("svc #0" : "+r"(x0), "+r"(x1) : "r"(x7) : "memory");
}

void child_main(void)
{
    child_puts("[elf] child process running in its own VSpace\n");
    child_signal(0);   /* CSpace slot 0 = badged result notification */
    for (;;) {
        __asm__ volatile("wfe");
    }
}
