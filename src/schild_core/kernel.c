void kernel_main(void) {
    volatile char *video = (volatile char *)0xB8000;
    const char *msg = "Schild TCB kernel entry\n";
    int i = 0;

    while (msg[i] != '\0') {
        video[i * 2] = msg[i];
        video[i * 2 + 1] = 0x0F;
        i++;
    }
}
