/*
 * Copyright (C) 2026 Alexander Irganov
 * SPDX-License-Identifier: GPL-2.0-only
 */

/*
 * Schild TCB Hardware I/O: outb / inb for x86_64 ports
 * Compiled with -m64 -ffreestanding -nostdlib (-nostdinc)
 * GUARANTEES upper bits of %edx cleared before outb/inb.
 */

void outb(int port, unsigned char value) {
    __asm__ volatile(
        "movl %[port], %%edx\n\t"
        "outb %b[val], %%dx"
        :
        : [port] "r" ((unsigned int)port),
          [val]  "a" (value)
        : "%edx"
    );
}

unsigned char inb(int port) {
    unsigned char result;
    __asm__ volatile(
        "movl %[port], %%edx\n\t"
        "inb %%dx, %b[res]"
        : [res]  "=a" (result)
        : [port] "r" ((unsigned int)port)
        : "%edx"
    );
    return result;
}void schild_debug_hex32(unsigned int v) {
    volatile char *uart = (volatile char*)0x3F8;
    static const char hex[] = "0123456789ABCDEF";
    int i;
    for (i = 28; i >= 0; i -= 4) {
        while (!(*(volatile char*)(0x3F8 + 5) & 0x20));
        *(volatile char*)0x3F8 = hex[(v >> i) & 15];
    }
    while (!(*(volatile char*)(0x3F8 + 5) & 0x20));
    *(volatile char*)0x3F8 = 10;
}
