/* Minimal seL4 AArch64 syscall shim: DebugPutChar (syscall id = -9). */
void seL4_DebugPutChar(char c) {
    register long x0 asm("x0") = (long)(unsigned char)c;
    register long x7 asm("x7") = -9;
    __asm__ volatile("svc #0" : : "r"(x0), "r"(x7) : "memory");
}

void seL4_DebugPutString(const char *s) {
    for (; *s; ++s) {
        seL4_DebugPutChar(*s);
    }
}
