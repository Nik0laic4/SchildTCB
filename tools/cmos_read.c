#include <stdio.h>
#include <sys/io.h>
int main(void) {
    if (iopl(3) != 0) { perror("iopl"); return 1; }
    for (int i = 0x2E; i <= 0x31; i++) {
        outb(i, 0x70);
        unsigned char v = inb(0x71);
        printf("CMOS 0x%02X = 0x%02X %c\n", i, v, (v >= 32 && v < 127) ? v : '.');
    }
    return 0;
}
