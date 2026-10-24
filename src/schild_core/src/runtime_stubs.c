/*
 * Copyright (C) 2026 Alexander Irganov
 * SPDX-License-Identifier: GPL-2.0-only
 */

/*
 * Schild TCB bare-metal runtime stubs + UART helper (C-string output)
 * CRITICAL: schild_uart_puts_c called from Ada via pragma Import(C),
 * GNAT auto-appends NUL terminator to string literal.
 */

/*
 * Schild TCB bare-metal runtime stubs + UART helper (inline asm port I/O)
 * CRITICAL: in bare-metal mode *(volatile char*)0x3F8 - this is MEMORY ACCESS,
 * not port I/O. outb/inb instructions required!
 */

/* Send one byte to COM1 (0x3F8) using port I/O (NOT memory access!) */
static void uart_putc(char c) {
    unsigned char scratch;
    /* Wait for THRE (bit 5 of LSR at 0x3FD) */
    do {
        __asm__ volatile("inb %1, %0" : "=a"(scratch) : "Nd"(0x3FD));
    } while (!(scratch & 0x20));
    /* Send byte to THR (0x3F8) */
    __asm__ volatile("outb %0, %1" : : "a"(c), "Nd"(0x3F8));
}

/* Diagnostic: set keyboard LEDs via i8042 (CapsLock=0x04, NumLock=0x02,
 * ScrollLock=0x01). Safe (only toggles LEDs). Used as a headless boot-progress
 * indicator on the T580, where there is no serial/VGA console. */
void schild_kbd_leds(unsigned char leds) {
    unsigned char status;
    int timeout;
    for (timeout = 0; timeout < 100000; timeout++) {
        __asm__ volatile("inb %1, %0" : "=a"(status) : "Nd"(0x64));
        if ((status & 0x02) == 0) break;
    }
    __asm__ volatile("outb %0, %1" : : "a"((unsigned char)0xED), "Nd"(0x60));
    for (timeout = 0; timeout < 100000; timeout++) {
        __asm__ volatile("inb %1, %0" : "=a"(status) : "Nd"(0x64));
        if ((status & 0x02) == 0) break;
    }
    __asm__ volatile("outb %0, %1" : : "a"(leds), "Nd"(0x60));
}

/* SMP: simple test-and-set spinlock for UART (shared by all cores) */
static volatile int uart_lock = 0;
static void uart_spin_lock(void) {
    while (__sync_lock_test_and_set(&uart_lock, 1))
        __asm__ volatile("pause");
}
static void uart_spin_unlock(void) {
    __sync_lock_release(&uart_lock);
}

/* Output len bytes, no trailing newline (internal — caller must hold lock) */
static void uart_write_unlocked(const char *msg, int len) {
    for (int i = 0; i < len; i++) {
        uart_putc(msg[i]);
    }
}

/* Forward declarations for the framebuffer console mirror (defined below). */
static void fb_putc(char c);
static void fb_puts(const char *msg, int len);

/* VGA text-mode mirror at 0xB8000. This is identity-mapped (0-64MB) and is
 * safe to write from the very first message, before any framebuffer setup. */
static volatile unsigned short *vga_text = (volatile unsigned short *)0xB8000UL;
static unsigned int vga_col = 0, vga_row = 0;

static void vga_putc(char c) {
    if (c == '\n') { vga_col = 0; vga_row++; }
    else if (c == '\r') { vga_col = 0; }
    else {
        vga_text[vga_row * 80 + vga_col] = (unsigned short)(unsigned char)c | 0x0F00u;
        if (++vga_col >= 80) { vga_col = 0; vga_row++; }
    }
    if (vga_row >= 25) {
        for (unsigned int r = 0; r < 24; r++)
            for (unsigned int c = 0; c < 80; c++)
                vga_text[r * 80 + c] = vga_text[(r + 1) * 80 + c];
        for (unsigned int c = 0; c < 80; c++)
            vga_text[24 * 80 + c] = 0x0F20u;
        vga_row = 24;
    }
}

static void vga_puts(const char *msg, int len) {
    for (int i = 0; i < len; i++) vga_putc(msg[i]);
}

/* Boot-log capture ring, persisted to the NVMe for post-boot inspection. */
#define SCHILD_LOG_SIZE 8192
char schild_log_buf[SCHILD_LOG_SIZE];
unsigned int schild_log_len = 0;

static void log_capture(const char *msg, int len) {
    for (int i = 0; i < len && schild_log_len < SCHILD_LOG_SIZE; i++)
        schild_log_buf[schild_log_len++] = msg[i];
}

/* Diagnostic: append an 8-digit hex value to the boot-log capture ring. */
void schild_log_hex32(unsigned int v) {
    char buf[8];
    for (int i = 7; i >= 0; i--) { buf[i] = "0123456789ABCDEF"[v & 0xF]; v >>= 4; }
    log_capture(buf, 8);
}

/* Output len bytes, no trailing newline */
void schild_uart_puts(const char *msg, int len) {
    uart_spin_lock();
    uart_write_unlocked(msg, len);
    log_capture(msg, len);
    fb_puts(msg, len);
    vga_puts(msg, len);
    uart_spin_unlock();
}

/* Output len bytes + CR+LF */
void schild_uart_putln(const char *msg, int len) {
    uart_spin_lock();
    uart_write_unlocked(msg, len);
    uart_putc('\r');
    uart_putc('\n');
    log_capture(msg, len);
    log_capture("\r\n", 2);
    fb_puts(msg, len);
    fb_putc('\r');
    fb_putc('\n');
    vga_puts(msg, len);
    vga_putc('\r');
    vga_putc('\n');
    uart_spin_unlock();
}

/* Helper: NUL-terminated C-string output (for panic messages) */
static void uart_puts(const char *msg) {
    for (int i = 0; msg[i]; i++) uart_putc(msg[i]);
}

/* ─── Stage 9: network debug bridge (core stub) ──────────────────────────
 * The standalone kernel has no audit log, so this bridge returns an empty
 * payload. The real implementation lives in the NetServer runtime
 * (tools/sel4/src/schild_net_runtime.c). Keeping a stub here means build.sh
 * still links 182 objects. */
void schild_debug_render(void *buffer, int max_len, int *actual_len) {
    (void)buffer; (void)max_len;
    if (actual_len) *actual_len = 0;
}

/* === Framebuffer C helpers === */
static unsigned int *schild_fb_base = 0;
static unsigned int schild_fb_w = 0, schild_fb_h = 0, schild_fb_pitch = 0;

/* Console margins (px). Laptop panels overscan a few pixels under the bezel,
 * so text drawn at (0,0) gets clipped at the top/left/right edges. These
 * offsets keep the boot log fully visible. Tune to taste. */
#define FB_MARGIN_LEFT_PX  40
#define FB_MARGIN_RIGHT_PX 40
#define FB_MARGIN_TOP_PX   40

/* Console line height (px): 16 px glyph + 4 px inter-line spacing. Without
 * the extra 4 px, adjacent lines touch (zero leading) and a fast-scrolling
 * log turns into unreadable mush. */
#define FB_LINE_HEIGHT_PX  20

/* 8×16 console font (ASCII 32-126, 95 chars, 16 rows each).
 * Row-major: schild_fb_font[row][col], col = ASCII - 32.
 * Glyphs: UNSCII 8-tall variant by viznut — Public Domain / CC-0
 * (https://github.com/viznut/unscii). */
const unsigned char schild_fb_font[16][95] = {
  {0x00, 0x18, 0x66, 0x6c, 0x18, 0x00, 0x38, 0x18, 0x0c, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0x3c, 0x18, 0x3c, 0x3c, 0x1c, 0x7e, 0x1c, 0x7e, 0x3c, 0x3c, 0x00, 0x00, 0x0c, 0x00, 0x60, 0x3c, 0x7c, 0x18, 0x7c, 0x3c, 0x78, 0x7e, 0x7e, 0x3c, 0x66, 0x7e, 0x06, 0xc6, 0x60, 0xc6, 0xc6, 0x3c, 0x7c, 0x3c, 0x7c, 0x3c, 0x7e, 0x66, 0x66, 0xc6, 0xc3, 0xc3, 0x7e, 0x3c, 0xc0, 0x3c, 0x10, 0x00, 0x18, 0x00, 0x60, 0x00, 0x06, 0x00, 0x1c, 0x00, 0x60, 0x18, 0x0c, 0x60, 0x38, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0e, 0x18, 0x70, 0x76},
  {0x00, 0x18, 0x66, 0x6c, 0x18, 0x00, 0x38, 0x18, 0x0c, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0x3c, 0x18, 0x3c, 0x3c, 0x1c, 0x7e, 0x1c, 0x7e, 0x3c, 0x3c, 0x00, 0x00, 0x0c, 0x00, 0x60, 0x3c, 0x7c, 0x18, 0x7c, 0x3c, 0x78, 0x7e, 0x7e, 0x3c, 0x66, 0x7e, 0x06, 0xc6, 0x60, 0xc6, 0xc6, 0x3c, 0x7c, 0x3c, 0x7c, 0x3c, 0x7e, 0x66, 0x66, 0xc6, 0xc3, 0xc3, 0x7e, 0x3c, 0xc0, 0x3c, 0x10, 0x00, 0x18, 0x00, 0x60, 0x00, 0x06, 0x00, 0x1c, 0x00, 0x60, 0x18, 0x0c, 0x60, 0x38, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0e, 0x18, 0x70, 0x76},
  {0x00, 0x18, 0x66, 0x6c, 0x3e, 0xc6, 0x6c, 0x18, 0x18, 0x18, 0x66, 0x18, 0x00, 0x00, 0x00, 0x06, 0x66, 0x38, 0x66, 0x66, 0x3c, 0x60, 0x30, 0x06, 0x66, 0x66, 0x18, 0x18, 0x18, 0x00, 0x30, 0x66, 0xc6, 0x3c, 0x66, 0x66, 0x6c, 0x60, 0x60, 0x66, 0x66, 0x18, 0x06, 0xcc, 0x60, 0xee, 0xe6, 0x66, 0x66, 0x66, 0x66, 0x66, 0x18, 0x66, 0x66, 0xc6, 0x66, 0x66, 0x06, 0x30, 0x60, 0x0c, 0x38, 0x00, 0x0c, 0x00, 0x60, 0x00, 0x06, 0x00, 0x30, 0x00, 0x60, 0x00, 0x00, 0x60, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x18, 0xdc},
  {0x00, 0x18, 0x66, 0x6c, 0x3e, 0xc6, 0x6c, 0x18, 0x18, 0x18, 0x66, 0x18, 0x00, 0x00, 0x00, 0x06, 0x66, 0x38, 0x66, 0x66, 0x3c, 0x60, 0x30, 0x06, 0x66, 0x66, 0x18, 0x18, 0x18, 0x00, 0x30, 0x66, 0xc6, 0x3c, 0x66, 0x66, 0x6c, 0x60, 0x60, 0x66, 0x66, 0x18, 0x06, 0xcc, 0x60, 0xee, 0xe6, 0x66, 0x66, 0x66, 0x66, 0x66, 0x18, 0x66, 0x66, 0xc6, 0x66, 0x66, 0x06, 0x30, 0x60, 0x0c, 0x38, 0x00, 0x0c, 0x00, 0x60, 0x00, 0x06, 0x00, 0x30, 0x00, 0x60, 0x00, 0x00, 0x60, 0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x18, 0x18, 0x18, 0xdc},
  {0x00, 0x18, 0x66, 0xfe, 0x60, 0xcc, 0x38, 0x30, 0x30, 0x0c, 0x3c, 0x18, 0x00, 0x00, 0x00, 0x0c, 0x6e, 0x18, 0x0c, 0x06, 0x6c, 0x7c, 0x60, 0x06, 0x66, 0x66, 0x18, 0x18, 0x30, 0x7e, 0x18, 0x06, 0xde, 0x66, 0x66, 0x60, 0x66, 0x60, 0x60, 0x60, 0x66, 0x18, 0x06, 0xd8, 0x60, 0xfe, 0xf6, 0x66, 0x66, 0x66, 0x66, 0x60, 0x18, 0x66, 0x66, 0xc6, 0x3c, 0x3c, 0x0c, 0x30, 0x30, 0x0c, 0x6c, 0x00, 0x06, 0x3c, 0x7c, 0x3c, 0x3e, 0x3c, 0x7c, 0x3e, 0x7c, 0x38, 0x0c, 0x66, 0x18, 0xcc, 0x7c, 0x3c, 0x7c, 0x3e, 0x7c, 0x3e, 0x7e, 0x66, 0x66, 0xc6, 0xc6, 0x66, 0x7e, 0x18, 0x18, 0x18, 0x00},
  {0x00, 0x18, 0x66, 0xfe, 0x60, 0xcc, 0x38, 0x30, 0x30, 0x0c, 0x3c, 0x18, 0x00, 0x00, 0x00, 0x0c, 0x6e, 0x18, 0x0c, 0x06, 0x6c, 0x7c, 0x60, 0x06, 0x66, 0x66, 0x18, 0x18, 0x30, 0x7e, 0x18, 0x06, 0xde, 0x66, 0x66, 0x60, 0x66, 0x60, 0x60, 0x60, 0x66, 0x18, 0x06, 0xd8, 0x60, 0xfe, 0xf6, 0x66, 0x66, 0x66, 0x66, 0x60, 0x18, 0x66, 0x66, 0xc6, 0x3c, 0x3c, 0x0c, 0x30, 0x30, 0x0c, 0x6c, 0x00, 0x06, 0x3c, 0x7c, 0x3c, 0x3e, 0x3c, 0x7c, 0x3e, 0x7c, 0x38, 0x0c, 0x66, 0x18, 0xcc, 0x7c, 0x3c, 0x7c, 0x3e, 0x7c, 0x3e, 0x7e, 0x66, 0x66, 0xc6, 0xc6, 0x66, 0x7e, 0x18, 0x18, 0x18, 0x00},
  {0x00, 0x18, 0x00, 0x6c, 0x3c, 0x18, 0x76, 0x00, 0x30, 0x0c, 0xff, 0x7e, 0x00, 0x7e, 0x00, 0x18, 0x76, 0x18, 0x18, 0x1c, 0xcc, 0x06, 0x7c, 0x0c, 0x3c, 0x3e, 0x00, 0x00, 0x60, 0x00, 0x0c, 0x0c, 0xde, 0x66, 0x7c, 0x60, 0x66, 0x7c, 0x7c, 0x6e, 0x7e, 0x18, 0x06, 0xf0, 0x60, 0xd6, 0xde, 0x66, 0x7c, 0x66, 0x7c, 0x3c, 0x18, 0x66, 0x66, 0xd6, 0x18, 0x18, 0x18, 0x30, 0x18, 0x0c, 0xc6, 0x00, 0x00, 0x06, 0x66, 0x60, 0x66, 0x66, 0x30, 0x66, 0x66, 0x18, 0x0c, 0x6c, 0x18, 0xfe, 0x66, 0x66, 0x66, 0x66, 0x66, 0x60, 0x30, 0x66, 0x66, 0xc6, 0x6c, 0x66, 0x0c, 0x70, 0x18, 0x0e, 0x00},
  {0x00, 0x18, 0x00, 0x6c, 0x3c, 0x18, 0x76, 0x00, 0x30, 0x0c, 0xff, 0x7e, 0x00, 0x7e, 0x00, 0x18, 0x76, 0x18, 0x18, 0x1c, 0xcc, 0x06, 0x7c, 0x0c, 0x3c, 0x3e, 0x00, 0x00, 0x60, 0x00, 0x0c, 0x0c, 0xde, 0x66, 0x7c, 0x60, 0x66, 0x7c, 0x7c, 0x6e, 0x7e, 0x18, 0x06, 0xf0, 0x60, 0xd6, 0xde, 0x66, 0x7c, 0x66, 0x7c, 0x3c, 0x18, 0x66, 0x66, 0xd6, 0x18, 0x18, 0x18, 0x30, 0x18, 0x0c, 0xc6, 0x00, 0x00, 0x06, 0x66, 0x60, 0x66, 0x66, 0x30, 0x66, 0x66, 0x18, 0x0c, 0x6c, 0x18, 0xfe, 0x66, 0x66, 0x66, 0x66, 0x66, 0x60, 0x30, 0x66, 0x66, 0xc6, 0x6c, 0x66, 0x0c, 0x70, 0x18, 0x0e, 0x00},
  {0x00, 0x18, 0x00, 0xfe, 0x06, 0x30, 0xdc, 0x00, 0x30, 0x0c, 0x3c, 0x18, 0x00, 0x00, 0x00, 0x30, 0x66, 0x18, 0x30, 0x06, 0xfe, 0x06, 0x66, 0x18, 0x66, 0x06, 0x00, 0x00, 0x30, 0x7e, 0x18, 0x18, 0xde, 0x7e, 0x66, 0x60, 0x66, 0x60, 0x60, 0x66, 0x66, 0x18, 0x06, 0xd8, 0x60, 0xc6, 0xce, 0x66, 0x60, 0x66, 0x6c, 0x06, 0x18, 0x66, 0x66, 0xfe, 0x3c, 0x18, 0x30, 0x30, 0x0c, 0x0c, 0x00, 0x00, 0x00, 0x3e, 0x66, 0x60, 0x66, 0x7e, 0x30, 0x66, 0x66, 0x18, 0x0c, 0x78, 0x18, 0xd6, 0x66, 0x66, 0x66, 0x66, 0x60, 0x3c, 0x30, 0x66, 0x66, 0xd6, 0x38, 0x66, 0x18, 0x18, 0x18, 0x18, 0x00},
  {0x00, 0x18, 0x00, 0xfe, 0x06, 0x30, 0xdc, 0x00, 0x30, 0x0c, 0x3c, 0x18, 0x00, 0x00, 0x00, 0x30, 0x66, 0x18, 0x30, 0x06, 0xfe, 0x06, 0x66, 0x18, 0x66, 0x06, 0x00, 0x00, 0x30, 0x7e, 0x18, 0x18, 0xde, 0x7e, 0x66, 0x60, 0x66, 0x60, 0x60, 0x66, 0x66, 0x18, 0x06, 0xd8, 0x60, 0xc6, 0xce, 0x66, 0x60, 0x66, 0x6c, 0x06, 0x18, 0x66, 0x66, 0xfe, 0x3c, 0x18, 0x30, 0x30, 0x0c, 0x0c, 0x00, 0x00, 0x00, 0x3e, 0x66, 0x60, 0x66, 0x7e, 0x30, 0x66, 0x66, 0x18, 0x0c, 0x78, 0x18, 0xd6, 0x66, 0x66, 0x66, 0x66, 0x60, 0x3c, 0x30, 0x66, 0x66, 0xd6, 0x38, 0x66, 0x18, 0x18, 0x18, 0x18, 0x00},
  {0x00, 0x00, 0x00, 0x6c, 0x7c, 0x66, 0xcc, 0x00, 0x18, 0x18, 0x66, 0x18, 0x18, 0x00, 0x18, 0x60, 0x66, 0x18, 0x60, 0x66, 0x0c, 0x66, 0x66, 0x18, 0x66, 0x0c, 0x18, 0x18, 0x18, 0x00, 0x30, 0x00, 0xc0, 0x66, 0x66, 0x66, 0x6c, 0x60, 0x60, 0x66, 0x66, 0x18, 0x66, 0xcc, 0x60, 0xc6, 0xc6, 0x66, 0x60, 0x6c, 0x66, 0x66, 0x18, 0x66, 0x3c, 0xee, 0x66, 0x18, 0x60, 0x30, 0x06, 0x0c, 0x00, 0x00, 0x00, 0x66, 0x66, 0x60, 0x66, 0x60, 0x30, 0x3e, 0x66, 0x18, 0x0c, 0x6c, 0x18, 0xd6, 0x66, 0x66, 0x7c, 0x3e, 0x60, 0x06, 0x30, 0x66, 0x3c, 0x7c, 0x6c, 0x3e, 0x30, 0x18, 0x18, 0x18, 0x00},
  {0x00, 0x00, 0x00, 0x6c, 0x7c, 0x66, 0xcc, 0x00, 0x18, 0x18, 0x66, 0x18, 0x18, 0x00, 0x18, 0x60, 0x66, 0x18, 0x60, 0x66, 0x0c, 0x66, 0x66, 0x18, 0x66, 0x0c, 0x18, 0x18, 0x18, 0x00, 0x30, 0x00, 0xc0, 0x66, 0x66, 0x66, 0x6c, 0x60, 0x60, 0x66, 0x66, 0x18, 0x66, 0xcc, 0x60, 0xc6, 0xc6, 0x66, 0x60, 0x6c, 0x66, 0x66, 0x18, 0x66, 0x3c, 0xee, 0x66, 0x18, 0x60, 0x30, 0x06, 0x0c, 0x00, 0x00, 0x00, 0x66, 0x66, 0x60, 0x66, 0x60, 0x30, 0x3e, 0x66, 0x18, 0x0c, 0x6c, 0x18, 0xd6, 0x66, 0x66, 0x7c, 0x3e, 0x60, 0x06, 0x30, 0x66, 0x3c, 0x7c, 0x6c, 0x3e, 0x30, 0x18, 0x18, 0x18, 0x00},
  {0x00, 0x18, 0x00, 0x6c, 0x18, 0xc6, 0x76, 0x00, 0x0c, 0x30, 0x00, 0x00, 0x18, 0x00, 0x18, 0xc0, 0x3c, 0x7e, 0x7e, 0x3c, 0x0c, 0x3c, 0x3c, 0x18, 0x3c, 0x38, 0x18, 0x18, 0x0c, 0x00, 0x60, 0x18, 0x7c, 0x66, 0x7c, 0x3c, 0x78, 0x7e, 0x60, 0x3e, 0x66, 0x7e, 0x3c, 0xc6, 0x7e, 0xc6, 0xc6, 0x3c, 0x60, 0x36, 0x66, 0x3c, 0x18, 0x3c, 0x18, 0xc6, 0xc3, 0x18, 0x7e, 0x3c, 0x03, 0x3c, 0x00, 0x00, 0x00, 0x3e, 0x7c, 0x3c, 0x3e, 0x3c, 0x30, 0x06, 0x66, 0x1e, 0x0c, 0x66, 0x1e, 0xc6, 0x66, 0x3c, 0x60, 0x06, 0x60, 0x7c, 0x1e, 0x3e, 0x18, 0x6c, 0xc6, 0x06, 0x7e, 0x0e, 0x18, 0x70, 0x00},
  {0x00, 0x18, 0x00, 0x6c, 0x18, 0xc6, 0x76, 0x00, 0x0c, 0x30, 0x00, 0x00, 0x18, 0x00, 0x18, 0xc0, 0x3c, 0x7e, 0x7e, 0x3c, 0x0c, 0x3c, 0x3c, 0x18, 0x3c, 0x38, 0x18, 0x18, 0x0c, 0x00, 0x60, 0x18, 0x7c, 0x66, 0x7c, 0x3c, 0x78, 0x7e, 0x60, 0x3e, 0x66, 0x7e, 0x3c, 0xc6, 0x7e, 0xc6, 0xc6, 0x3c, 0x60, 0x36, 0x66, 0x3c, 0x18, 0x3c, 0x18, 0xc6, 0xc3, 0x18, 0x7e, 0x3c, 0x03, 0x3c, 0x00, 0x00, 0x00, 0x3e, 0x7c, 0x3c, 0x3e, 0x3c, 0x30, 0x06, 0x66, 0x1e, 0x0c, 0x66, 0x1e, 0xc6, 0x66, 0x3c, 0x60, 0x06, 0x60, 0x7c, 0x1e, 0x3e, 0x18, 0x6c, 0xc6, 0x06, 0x7e, 0x0e, 0x18, 0x70, 0x00},
  {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7c, 0x00, 0x00, 0x78, 0x00, 0x00, 0x00, 0x00, 0x00, 0x60, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3c, 0x00, 0x00, 0x00, 0x00, 0x00},
  {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7c, 0x00, 0x00, 0x78, 0x00, 0x00, 0x00, 0x00, 0x00, 0x60, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3c, 0x00, 0x00, 0x00, 0x00, 0x00},
};

/* Enable Write-Combining for the framebuffer via IA32_PAT. boot.S maps the
 * framebuffer pages with the PAT bit set (PDE.PAT=1, PCD=0, PWT=0 -> PAT entry
 * 4). Setting PAT entry 4 to WC turns the uncached framebuffer into
 * write-combining, which greatly speeds up the text console (scroll/glyph/clear). */
static void enable_fb_write_combining(void) {
    unsigned int lo, hi;
    __asm__ volatile("rdmsr" : "=a"(lo), "=d"(hi) : "c"(0x277));
    lo = (lo & ~0x0F000000u) | (0x01u << 24);  /* PAT[4] = WC (0x01) */
    __asm__ volatile("wrmsr" : : "a"(lo), "d"(hi), "c"(0x277));
}

void schild_fb_init(unsigned int *addr, unsigned int w, unsigned int h, unsigned int pitch) {
    /* boot.S maps the framebuffer only in the 0xC0000000..0xFFFFFFFF window
     * (one 2 MB huge page). If the GOP framebuffer is outside that window
     * (e.g. above 4 GB on UEFI), it is unmapped and any write would #PF. */
    unsigned long a = (unsigned long)addr;
    if (a < 0xC0000000UL || a >= 0x100000000UL) return;  /* skip console */
    schild_fb_base = addr; schild_fb_w = w; schild_fb_h = h; schild_fb_pitch = pitch;
    enable_fb_write_combining();
    /* boot.S now maps the whole framebuffer (pitch × height rounded up to
     * 2 MB pages), so the full height is usable — no clamping needed. */
    /* Clear the whole framebuffer to black (the GOP framebuffer still holds
     * GRUB's menu / boot text, so clear it for a clean console start). */
    { /* clear whole framebuffer with 64-bit stores (FHD pitch is 8-byte aligned) */
        unsigned long long *a = (unsigned long long *)addr;
        unsigned long npix = (unsigned long)(pitch / 4) * schild_fb_h;
        unsigned long i;
        for (i = 0; i + 1 < npix; i += 2) a[i >> 1] = 0ULL;
        if (npix & 1) addr[npix - 1] = 0x00000000;
    }
}

void schild_fb_putpixel(unsigned int x, unsigned int y, unsigned int color) {
    if (!schild_fb_base || x >= schild_fb_w || y >= schild_fb_h) return;
    schild_fb_base[y * (schild_fb_pitch/4) + x] = color;
}

void schild_fb_scroll(unsigned int char_h, unsigned int fb_h, unsigned int fb_p) {
    if (!schild_fb_base) return;
    unsigned char *b = (unsigned char*)schild_fb_base;
    /* Scroll only the content region (below the top margin), so the top
     * margin stays fixed and text never slides back under the bezel.
     * 64-bit copy: the old byte-by-byte loop moved ~8 MB of uncached
     * framebuffer on every scroll, which dominated boot latency. */
    unsigned char *dst = b + (unsigned long)FB_MARGIN_TOP_PX * fb_p;
    unsigned char *src = dst + (unsigned long)char_h * fb_p;
    unsigned long nbytes = (unsigned long)(fb_h - FB_MARGIN_TOP_PX - char_h) * fb_p;
    unsigned long i;
    for (i = 0; i + 8 <= nbytes; i += 8)
        *(volatile unsigned long long *)(dst + i) = *(volatile unsigned long long *)(src + i);
    for (; i < nbytes; i++) dst[i] = src[i];
    unsigned char *last = b + (unsigned long)(fb_h - char_h) * fb_p;
    unsigned long nlast = (unsigned long)char_h * fb_p;
    for (i = 0; i + 8 <= nlast; i += 8)
        *(volatile unsigned long long *)(last + i) = 0ULL;
    for (; i < nlast; i++) last[i] = 0;
}

/* === Framebuffer text console mirror === */
static unsigned int fb_cur_x = 0, fb_cur_y = 0;

static void fb_putc(char c) {
    if (!schild_fb_base || !schild_fb_w || !schild_fb_h) return;
    unsigned int cols = (schild_fb_w - FB_MARGIN_LEFT_PX - FB_MARGIN_RIGHT_PX) / 8;
    unsigned int rows = (schild_fb_h - FB_MARGIN_TOP_PX) / FB_LINE_HEIGHT_PX;
    if (c == '\n') {
        fb_cur_x = 0; fb_cur_y++;
    } else if (c == '\r') {
        fb_cur_x = 0;
    } else {
        int ci = (int)(unsigned char)c - 32;
        if (ci < 0 || ci > 94) ci = 0;
        if (fb_cur_x >= cols) { fb_cur_x = 0; fb_cur_y++; }
        for (unsigned int row = 0; row < 16; row++) {
            unsigned char bits = schild_fb_font[row][ci];
            unsigned int *glyph_row = &schild_fb_base[
                (FB_MARGIN_TOP_PX + fb_cur_y * FB_LINE_HEIGHT_PX + row) * (schild_fb_pitch / 4)
                + FB_MARGIN_LEFT_PX + fb_cur_x * 8];
            for (unsigned int col = 0; col < 8; col++)
                glyph_row[col] = (bits & (0x80 >> col)) ? 0x00FFFFFFu : 0x00000000u;
        }
        fb_cur_x++;
    }
    if (fb_cur_y >= rows) {
        schild_fb_scroll(FB_LINE_HEIGHT_PX, schild_fb_h, schild_fb_pitch);
        fb_cur_y = rows - 1;
    }
}

static void fb_puts(const char *msg, int len) {
    for (int i = 0; i < len; i++) fb_putc(msg[i]);
}

/* --- Emergency reboot via i8042 keyboard controller -----------------------
 * Pulse the CPU reset line (0xFE to port 0x64). Fatal-exception handlers use
 * this so a remotely-triggered fault reboots the machine instead of wedging
 * it in an infinite loop. Falls back to halt if the reset line never fires. */
static void system_reset(void) {
    unsigned char status;
    for (int i = 0; i < 100000; i++) {
        __asm__ volatile("inb %1, %0" : "=a"(status) : "Nd"(0x64));
        if ((status & 0x02) == 0) break;   /* input buffer empty */
    }
    __asm__ volatile("outb %0, %1" : : "a"((unsigned char)0xFE), "Nd"(0x64));
    for (;;) __asm__ volatile("hlt");
}

/* RDTSC: hardware timestamp counter — entropy source for the TCP ISN and the
 * clock for TCP connection idle timeouts (exported to Ada). */
unsigned long long schild_rdtsc(void) {
    unsigned int lo, hi;
    __asm__ volatile("rdtsc" : "=a"(lo), "=d"(hi));
    return ((unsigned long long)hi << 32) | lo;
}

/* --- Unwind stubs --- */
void _Unwind_Resume(void) { system_reset(); }

/* --- GNAT runtime check stubs --- */
void __gnat_rcheck_CE_Access_Check(void)  { uart_puts("\r\n[PANIC] CE_Access_Check\r\n"); system_reset(); }
void __gnat_rcheck_CE_Index_Check(void)   { uart_puts("\r\n[PANIC] CE_Index_Check\r\n"); system_reset(); }
void __gnat_rcheck_CE_Range_Check(void)   { uart_puts("\r\n[PANIC] CE_Range_Check\r\n"); system_reset(); }
void __gnat_rcheck_CE_Overflow_Check(void){ uart_puts("\r\n[PANIC] CE_Overflow_Check\r\n"); system_reset(); }
void __gnat_rcheck_CE_Invalid_Data(void)  { uart_puts("\r\n[PANIC] CE_Invalid_Data\r\n"); system_reset(); }
void __gnat_rcheck_CE_Divide_By_Zero(void){ uart_puts("\r\n[PANIC] CE_Divide_By_Zero\r\n"); system_reset(); }
void __gnat_rcheck_PE_Stream_Operation(const char *f,int l){ (void)f;(void)l; uart_puts("\r\n[PANIC] PE_Stream_Operation\r\n"); system_reset(); }
void __gnat_last_chance_handler(const char *s,int l) { (void)s;(void)l; uart_puts("\r\n[PANIC] last_chance_handler\r\n"); system_reset(); }
void __gnat_raise_exception(void)         { uart_puts("\r\n[PANIC] GNAT exception\r\n"); system_reset(); }
void __gnat_personality_v0(void)          { uart_puts("\r\n[PANIC] personality_v0\r\n"); system_reset(); }

/* --- GNAT secondary stack: per-core bounded stacks --------------------------
 * The previous single 4 KB buffer (wrap-around, no lock) silently corrupted
 * data under SMP. Each core now owns a private 8 KB stack; the core id comes
 * from the xAPIC local-APIC ID register. Overflow panics instead of wrapping. */
#define SS_CORES  16
#define SS_SIZE   8192

static char ss_stacks[SS_CORES][SS_SIZE] __attribute__((aligned(16)));
static unsigned int ss_off[SS_CORES];

static int ss_cpu_index(void) {
    /* xAPIC local APIC ID register (MMIO at 0xFEE00020, mapped by boot.S). */
    volatile unsigned int *lapic_id = (volatile unsigned int *)0xFEE00020UL;
    int c = (int)((*lapic_id >> 24) & 0xFF);
    return (c >= 0 && c < SS_CORES) ? c : 0;
}

void *system__secondary_stack__ss_allocate(unsigned long size) {
    int c = ss_cpu_index();
    unsigned long n = (size + 15UL) & ~15UL;   /* 16-byte aligned */
    if (ss_off[c] + n > SS_SIZE) {
        uart_puts("\r\n[PANIC] secondary stack overflow\r\n");
        system_reset();
    }
    void *p = &ss_stacks[c][ss_off[c]];
    ss_off[c] += (unsigned int)n;
    return p;
}
void *system__secondary_stack__ss_alloc(unsigned long sz){ return system__secondary_stack__ss_allocate(sz); }
unsigned long system__secondary_stack__ss_size(void){
    int c = ss_cpu_index();
    return (unsigned long)(SS_SIZE - ss_off[c]);
}
void *system__secondary_stack__ss_mark(void){
    int c = ss_cpu_index();
    return &ss_stacks[c][ss_off[c]];
}
void system__secondary_stack__ss_release(void*m){
    int c = ss_cpu_index();
    unsigned long mark = (unsigned long)((char *)m - &ss_stacks[c][0]);
    if (mark <= SS_SIZE) ss_off[c] = (unsigned int)mark;
}

/* --- GNAT string concatenation (correct implementations) ---------------------
 * The previous no-op stubs silently produced garbage for runtime `&`. These
 * copy each operand into the result buffer in order. Static `&` of literals is
 * folded at compile time and never reaches these; runtime `&` now works. */
static void str_copy(char *dst, const char *src, unsigned long n) {
    for (unsigned long i = 0; i < n; i++) dst[i] = src[i];
}
void system__concat_2__str_concat_2(void*r,const void*s1,const void*s2,unsigned long l1,unsigned long l2){char*d=(char*)r;str_copy(d,(const char*)s1,l1);str_copy(d+l1,(const char*)s2,l2);}
void system__concat_3__str_concat_3(void*r,const void*s1,const void*s2,const void*s3,unsigned long l1,unsigned long l2,unsigned long l3){char*d=(char*)r;str_copy(d,(const char*)s1,l1);str_copy(d+l1,(const char*)s2,l2);str_copy(d+l1+l2,(const char*)s3,l3);}
void system__concat_4__str_concat_4(void*r,const void*s1,const void*s2,const void*s3,const void*s4,unsigned long l1,unsigned long l2,unsigned long l3,unsigned long l4){char*d=(char*)r;str_copy(d,(const char*)s1,l1);str_copy(d+l1,(const char*)s2,l2);str_copy(d+l1+l2,(const char*)s3,l3);str_copy(d+l1+l2+l3,(const char*)s4,l4);}
void system__concat_5__str_concat_5(void*r,const void*s1,const void*s2,const void*s3,const void*s4,const void*s5,unsigned long l1,unsigned long l2,unsigned long l3,unsigned long l4,unsigned long l5){char*d=(char*)r;str_copy(d,(const char*)s1,l1);str_copy(d+l1,(const char*)s2,l2);str_copy(d+l1+l2,(const char*)s3,l3);str_copy(d+l1+l2+l3,(const char*)s4,l4);str_copy(d+l1+l2+l3+l4,(const char*)s5,l5);}
void system__concat_6__str_concat_6(void*r,const void*s1,const void*s2,const void*s3,const void*s4,const void*s5,const void*s6,unsigned long l1,unsigned long l2,unsigned long l3,unsigned long l4,unsigned long l5,unsigned long l6){char*d=(char*)r;str_copy(d,(const char*)s1,l1);str_copy(d+l1,(const char*)s2,l2);str_copy(d+l1+l2,(const char*)s3,l3);str_copy(d+l1+l2+l3,(const char*)s4,l4);str_copy(d+l1+l2+l3+l4,(const char*)s5,l5);str_copy(d+l1+l2+l3+l4+l5,(const char*)s6,l6);}
void system__concat_7__str_concat_7(void*r,const void*s1,const void*s2,const void*s3,const void*s4,const void*s5,const void*s6,const void*s7,unsigned long l1,unsigned long l2,unsigned long l3,unsigned long l4,unsigned long l5,unsigned long l6,unsigned long l7){char*d=(char*)r;str_copy(d,(const char*)s1,l1);str_copy(d+l1,(const char*)s2,l2);str_copy(d+l1+l2,(const char*)s3,l3);str_copy(d+l1+l2+l3,(const char*)s4,l4);str_copy(d+l1+l2+l3+l4,(const char*)s5,l5);str_copy(d+l1+l2+l3+l4+l5,(const char*)s6,l6);str_copy(d+l1+l2+l3+l4+l5+l6,(const char*)s7,l7);}

/* --- GNAT integer image stubs --- */
void system__img_int__impl__image_integer(void*buf,void*len,long v){
    char*p=(char*)buf; int i=0;
    if(v<0){p[i++]='-';v=-v;}
    if(v==0){p[i++]='0';}
    else{char t[21];int j=0;while(v>0){t[j++]='0'+(v%10);v/=10;}while(j>0)p[i++]=t[--j];}
    *(int*)len=i;
}

/* --- Memory stubs: dynamic allocation is unsupported ------------------------
 * A freestanding kernel must not allocate dynamically; every object must be a
 * fixed, compile-time-sized one. These panic loudly so a stray call is caught
 * immediately instead of silently returning NULL (delayed NULL-dereference). */
void *malloc(unsigned long s){
    (void)s;
    uart_puts("\r\n[PANIC] malloc() called - dynamic allocation unsupported\r\n");
    system_reset();
    return 0;  /* unreachable */
}
void free(void*p){(void)p;}  /* no-op: nothing is ever allocated */
void *calloc(unsigned long n,unsigned long s){
    (void)n;(void)s;
    uart_puts("\r\n[PANIC] calloc() called - dynamic allocation unsupported\r\n");
    system_reset();
    return 0;
}
void *realloc(void*p,unsigned long s){
    (void)p;(void)s;
    uart_puts("\r\n[PANIC] realloc() called - dynamic allocation unsupported\r\n");
    system_reset();
    return 0;
}
void __libc_csu_init(void){}
void __libc_csu_fini(void){}
int atexit(void(*f)(void)){(void)f;return 0;}

/* --- memcpy/memset/memmove --- */
void *memcpy(void*d,const void*s,unsigned long n){
    char*dd=(char*)d;const char*ss=(const char*)s;
    for(unsigned long i=0;i<n;i++)dd[i]=ss[i]; return d;
}
void *memset(void*s,int c,unsigned long n){
    char*p=(char*)s; for(unsigned long i=0;i<n;i++)p[i]=(char)c; return s;
}
void *memmove(void*d,const void*s,unsigned long n){
    char*dd=(char*)d;const char*ss=(const char*)s;
    if(dd<ss){for(unsigned long i=0;i<n;i++)dd[i]=ss[i];}
    else{for(unsigned long i=n;i>0;i--)dd[i-1]=ss[i-1];}
    return d;
}
void abort(void) {
    uart_puts("\r\n[PANIC] abort() called\r\n"); system_reset();
}
/* e1000e driver helpers: convert Ada object addresses to 64-bit integers */
unsigned long long schild_ptr_to_u64(void *ptr) {
    return (unsigned long long)(unsigned long)ptr;
}
/* DMA physical address: Ring 0 is identity-mapped, so virtual == physical. */
unsigned long long schild_dma_phys(void *ptr) {
    return (unsigned long long)(unsigned long)ptr;
}
unsigned int schild_ptr_to_u32_low(void *ptr) {
    return (unsigned int)((unsigned long long)(unsigned long)ptr & 0xFFFFFFFF);
}

/* Map a 2MB MMIO page in pd_table2 (covers 3-4 GB region).
 * pd_table2 is exported from boot.S (global symbol), identity-mapped.
 * This avoids hardcoded addresses that shift between builds.
 *
 * Why 2MB pages: BAR0 addresses of PCIe devices (e1000e: 0xFEB00000,
 * NVMe: 0xE8000000, APIC: 0xFEE00000) are in the 3-4GB range.
 * pd_table2 maps this range via PDPT[3]. Each PDE maps 2MB.
 * Full TLB flush via CR3 reload ensures the new mapping is visible. */
extern unsigned long long pd_table2[512];

void schild_map_mmio_2mb(unsigned long long phys_addr) {
    unsigned long long offset = phys_addr - 0xC0000000ULL;
    unsigned int idx = (unsigned int)(offset >> 21);
    if (idx < 512) {
        pd_table2[idx] = (phys_addr & 0xFFFFFFFFFFE00000ULL) | 0x83ULL;
        __asm__ volatile("invlpg (%0)" : : "r" (phys_addr) : "memory");
        /* Reload CR3 to flush all TLB entries — ensures new mapping visible */
        __asm__ volatile(
            "mov %%cr3, %%rax\n\t"
            "mov %%rax, %%cr3\n\t"
            : : : "rax", "memory"
        );
    }
}
/* SMP: write 8 bytes to physical address (used by trampoline setup) */
void schild_phys_write64(unsigned long long addr, unsigned long long val) {
    *(volatile unsigned long long *)addr = val;
}
/* SMP: copy trampoline code from kernel .text to 0x8000 */
extern char smp_trampoline_start[];
extern char smp_trampoline_end[];

/* Get kernel_end address (linker symbol) — for seL4 BootInfo */
extern char kernel_end;
unsigned long long schild_get_kernel_end(void) {
    return (unsigned long long)&kernel_end;
}

void schild_copy_trampoline(void) {
    unsigned long size = (unsigned long)(smp_trampoline_end - smp_trampoline_start);
    volatile char *dst = (volatile char *)0x8000;
    for (unsigned long i = 0; i < size; i++) {
        dst[i] = smp_trampoline_start[i];
    }
}
int memcmp(const void *a, const void *b, unsigned long n) { const unsigned char *ca = a, *cb = b; for (unsigned long i=0; i<n; i++) { if (ca[i]!=cb[i]) return ca[i]-cb[i]; } return 0; }

/* === DMA Cache Coherence for Real Hardware (ThinkPad T580) === */
/* WBINVD: Write-Back and Invalidate Cache — full cache flush.
   Required on real x86_64 before DMA to ensure device sees current data.
   NOTE: Ring-0 only, QEMU no-op. */
void schild_wbinvd(void) {
    __asm__ volatile("wbinvd" : : : "memory");
}

/* CLFLUSH: Flush a single cache line (64 bytes).
   Used before handing TX descriptor to e1000e DMA engine. */
void schild_clflush(void *addr) {
    __asm__ volatile("clflush (%0)" : : "r"(addr) : "memory");
}

/* NVMe: read byte from external ACQ (SeaBIOS DMA buffer) */
static unsigned long long nvme_ext_acq = 0;
void schild_nvme_set_ext_acq(unsigned long long addr) { nvme_ext_acq = addr; }
unsigned char schild_nvme_read_acq(unsigned int off) {
    if (!nvme_ext_acq) return 0;
    return *(volatile unsigned char *)(nvme_ext_acq + off);
}

/* Poll SeaBIOS ACQ: check up to 1024 bytes for any non-zero data */
int schild_nvme_poll_acq(void) {
    if (!nvme_ext_acq) return 0;
    volatile unsigned char *acq = (volatile unsigned char *)nvme_ext_acq;
    for (int i = 0; i < 1024; i++) {
        if (acq[i] != 0) return 1;
    }
    return 0;
}
