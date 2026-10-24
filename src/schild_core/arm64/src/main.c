/* Minimal seL4 root task (C) — prints via DebugPutChar syscall, then halts. */
void seL4_DebugPutString(const char *s);

void main(void) {
    seL4_DebugPutString("Hello, Schild TCB (ARM64 root task)!\n");
    for (;;) {
    }
}
