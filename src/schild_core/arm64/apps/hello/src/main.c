/* Minimal seL4 AArch64 root task — prints bootinfo via DebugPutChar syscall. */
#include <autoconf.h>
#include <sel4/sel4.h>
#include <sel4runtime.h>

static void put_string(const char *s) {
    for (; *s; ++s) {
        seL4_DebugPutChar(*s);
    }
}

static void put_hex(unsigned long v) {
    put_string("0x");
    for (int i = 60; i >= 0; i -= 4) {
        int d = (int)((v >> i) & 0xf);
        seL4_DebugPutChar((char)(d < 10 ? '0' + d : 'a' + d - 10));
    }
}

int main(void) {
    seL4_BootInfo *bi = sel4runtime_bootinfo();
    put_string("Hello, Schild TCB (ARM64 root task)!\n");
    if (bi) {
        put_string("numNodes=");      put_hex(bi->numNodes);      put_string("\n");
        put_string("numIOPTLevels="); put_hex(bi->numIOPTLevels); put_string("\n");
        put_string("ipcBuffer=");     put_hex((unsigned long)bi->ipcBuffer); put_string("\n");
    }
    for (;;) {
    }
    return 0;
}
