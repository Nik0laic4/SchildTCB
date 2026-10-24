/*
 * Copyright (C) 2026 Alexander Irganov
 * SPDX-License-Identifier: GPL-2.0-only
 */

static void raw_uart_putc(char c){unsigned char s;do{__asm__ volatile("inb %1,%0":"=a"(s):"Nd"(0x3FD));}while(!(s&0x20));__asm__ volatile("outb %0,%1"::"a"(c),"Nd"(0x3F8));}
static void uart_puts(const char*m){for(int i=0;m[i];i++)raw_uart_putc(m[i]);}
static void apic_eoi(void){*(volatile unsigned int*)0xFEE000B0=0;}
extern void schild_map_mmio_2mb(unsigned long long);
/* Emergency reboot: pulse the CPU reset line via the i8042 controller
 * (0xFE to port 0x64), so a fatal fault reboots instead of wedging forever. */
static void system_reset(void){
    unsigned char s; int i;
    for (i = 0; i < 100000; i++) {
        __asm__ volatile("inb %1,%0":"=a"(s):"Nd"(0x64));
        if ((s & 0x02) == 0) break;
    }
    __asm__ volatile("outb %0,%1"::"a"((unsigned char)0xFE),"Nd"(0x64));
    for(;;) __asm__("hlt");
}
static void apic_init(void){
    /* Enable Local APIC via Spurious Interrupt Vector Register */
    volatile unsigned int *lapic = (volatile unsigned int*)0xFEE00000;
    lapic[0xF0 / 4] = lapic[0xF0 / 4] | 0x1FF;  /* APIC Enable + vector 0xFF */
}
static unsigned long long irq_counts[256];
#define PANIC(m) do{uart_puts("\r\n[PANIC] "m"\r\n");system_reset();}while(0)
#define TRAP(m) do{uart_puts("\r\n[TRAP] "m"\r\n");apic_eoi();}while(0)

__attribute__((interrupt)) void eDE(void*f){(void)f;PANIC("#DE Divide Error");}
__attribute__((interrupt)) void eDB(void*f){(void)f;TRAP("#DB Debug");}
__attribute__((interrupt)) void eNMI(void*f){(void)f;PANIC("NMI");}
__attribute__((interrupt)) void eBP(void*f){(void)f;TRAP("#BP Breakpoint");}
__attribute__((interrupt)) void eOF(void*f){(void)f;PANIC("#OF Overflow");}
__attribute__((interrupt)) void eBR(void*f){(void)f;PANIC("#BR Bound Range");}
__attribute__((interrupt)) void eUD(void*f){(void)f;PANIC("#UD Invalid Opcode");}
__attribute__((interrupt)) void eNM(void*f){(void)f;PANIC("#NM Device NA");}
__attribute__((interrupt)) void eDF(void*f){(void)f;PANIC("#DF Double Fault");}
__attribute__((interrupt)) void eTS(void*f){(void)f;PANIC("#TS Invalid TSS");}
__attribute__((interrupt)) void eNP(void*f){(void)f;PANIC("#NP Segment NP");}
__attribute__((interrupt)) void eSS(void*f){(void)f;PANIC("#SS Stack Fault");}
__attribute__((interrupt)) void eGP(void*f){(void)f;PANIC("#GP General Protection");}
__attribute__((interrupt)) void ePF(void*f){(void)f;uart_puts("\r\n[PANIC] #PF Page Fault\r\n");system_reset();}
__attribute__((interrupt)) void eMF(void*f){(void)f;PANIC("#MF FPU Error");}

__attribute__((interrupt)) void irq1_kbd(void*f){(void)f;unsigned char sc;__asm__ volatile("inb %1,%0":"=a"(sc):"Nd"(0x60));irq_counts[0x21]++;apic_eoi();}

/* Spurious LAPIC interrupt (vector 0xFF, set by apic_init): acknowledge and
 * drop. Without this gate the C raw IDT leaves 0xFF absent, so enabling
 * interrupts (sti) on real hardware triggers a spurious IRQ -> #GP -> reset. */
__attribute__((interrupt)) void spurious_irq(void*f){(void)f;apic_eoi();}

extern void schild_kernel_logic__tick(void);
extern void schild_raw_irq_handler(void);

extern void schild_lapic_timer_start(void);

extern void schild_kernel_logic__tick(void);

__attribute__((interrupt)) void irq0_tmr(void*f){
    (void)f;
    /* Save XMM (Ada Tick() uses SSE) */
    __asm__ volatile(
        "sub $512, %%rsp\n\t"
        "movaps %%xmm0,  0x000(%%rsp)\n\t"
        "movaps %%xmm1,  0x010(%%rsp)\n\t"
        "movaps %%xmm2,  0x020(%%rsp)\n\t"
        "movaps %%xmm3,  0x030(%%rsp)\n\t"
        "movaps %%xmm4,  0x040(%%rsp)\n\t"
        "movaps %%xmm5,  0x050(%%rsp)\n\t"
        "movaps %%xmm6,  0x060(%%rsp)\n\t"
        "movaps %%xmm7,  0x070(%%rsp)\n\t"
        "movaps %%xmm8,  0x080(%%rsp)\n\t"
        "movaps %%xmm9,  0x090(%%rsp)\n\t"
        "movaps %%xmm10, 0x0A0(%%rsp)\n\t"
        "movaps %%xmm11, 0x0B0(%%rsp)\n\t"
        "movaps %%xmm12, 0x0C0(%%rsp)\n\t"
        "movaps %%xmm13, 0x0D0(%%rsp)\n\t"
        "movaps %%xmm14, 0x0E0(%%rsp)\n\t"
        "movaps %%xmm15, 0x0F0(%%rsp)\n\t"
        : : : "memory"
    );
    /* LAPIC EOI */
    *(volatile unsigned int*)0xFEE000B0 = 0;
    /* PIC EOI */
    __asm__ volatile("outb %0,%1" :: "a"((unsigned char)0x20), "Nd"(0x20));
    /* Call Ada scheduler tick */
    schild_kernel_logic__tick();
    /* Restore XMM */
    __asm__ volatile(
        "movaps 0x000(%%rsp), %%xmm0\n\t"
        "movaps 0x010(%%rsp), %%xmm1\n\t"
        "movaps 0x020(%%rsp), %%xmm2\n\t"
        "movaps 0x030(%%rsp), %%xmm3\n\t"
        "movaps 0x040(%%rsp), %%xmm4\n\t"
        "movaps 0x050(%%rsp), %%xmm5\n\t"
        "movaps 0x060(%%rsp), %%xmm6\n\t"
        "movaps 0x070(%%rsp), %%xmm7\n\t"
        "movaps 0x080(%%rsp), %%xmm8\n\t"
        "movaps 0x090(%%rsp), %%xmm9\n\t"
        "movaps 0x0A0(%%rsp), %%xmm10\n\t"
        "movaps 0x0B0(%%rsp), %%xmm11\n\t"
        "movaps 0x0C0(%%rsp), %%xmm12\n\t"
        "movaps 0x0D0(%%rsp), %%xmm13\n\t"
        "movaps 0x0E0(%%rsp), %%xmm14\n\t"
        "movaps 0x0F0(%%rsp), %%xmm15\n\t"
        "add $512, %%rsp\n\t"
        : : : "memory"
    );
}

void schild_apic_init(void) { apic_init(); }

/* Mask all LAPIC LVT, then configure LAPIC Timer for ONE-SHOT mode.
 * One-shot avoids race conditions with periodic timer:
 * handler does EOI, Tick restarts timer, hlt waits for next. */
void schild_lapic_mask_all(void) {
    volatile unsigned int *lapic = (volatile unsigned int *)0xFEE00000;
    lapic[0x320 / 4] |= (1 << 16);  /* Timer — mask it */
    lapic[0x330 / 4] |= (1 << 16);  /* Perf counters */
    lapic[0x340 / 4] |= (1 << 16);  /* Perf counters 2 */
    /* LINT0: ExtINT mode (required for PIC interrupt delivery!).
     * Delivery Mode=111 (ExtINT), edge-triggered, unmasked, vector ignored. */
    lapic[0x350 / 4] = 0x0700;       /* LINT0: ExtINT, unmasked */
    lapic[0x360 / 4] |= (1 << 16);  /* LINT1 */
    lapic[0x370 / 4] |= (1 << 16);  /* Error */
    lapic[0x380 / 4] |= (1 << 16);  /* Thermal sensor */

    /* One-shot mode: bit 17=0, vector=0x20, unmasked */
    lapic[0x3E0 / 4] = 0x3;         /* Divide Config: divisor=16 */
    lapic[0x320 / 4] = 0x20;         /* vector 0x20, one-shot, unmasked */
    /* Initial Count set later via schild_lapic_timer_start() */

    uart_puts("[LAPIC] LINT0 ExtINT + one-shot timer (vector 0x20)\r\n");
}

/* Start LAPIC Timer for one-shot interrupt after ~10ms */
void schild_lapic_timer_start(void) {
    volatile unsigned int *lapic = (volatile unsigned int *)0xFEE00000;
    lapic[0x380 / 4] = 0x000F4240;   /* ~10ms at 1GHz bus, divisor 16 */
}


/* Mask all IOAPIC interrupt pins EXCEPT pin 2 (PIT).
 * PIT IRQ routed via IOAPIC pin 2 → vector 0x20, edge, physical dest. */
void schild_ioapic_mask_all(void) {
    /* Map IOAPIC MMIO if not already mapped */
    schild_map_mmio_2mb(0xFEC00000ULL);
    volatile unsigned int *ioapic = (volatile unsigned int *)0xFEC00000;
    /* First: mask ALL 24 pins */
    for (int irq = 0; irq < 24; irq++) {
        ioapic[0x00 / 4] = 0x10 + 2 * irq;
        unsigned int low = ioapic[0x10 / 4];
        low |= (1 << 16);
        ioapic[0x00 / 4] = 0x10 + 2 * irq;
        ioapic[0x10 / 4] = low;
    }
    /* Unmask and configure IOAPIC pin 2 (PIT): vector 0x20, physical, edge, unmasked */
    ioapic[0x00 / 4] = 0x10 + 2 * 2;   /* IOREDTBL[2] low */
    ioapic[0x10 / 4] = 0x20;            /* vector 0x20, unmasked (bit 16=0), physical (bit 11=0), edge (bit 15=0) */
    uart_puts("[IOAPIC] Pin 2 (PIT) unmasked → vector 0x20; rest masked\r\n");
}

/* Unmask a single IOAPIC pin with the given vector.
 * Used for device interrupts (e1000e, NVMe, etc.) */
void schild_ioapic_unmask_pin(unsigned int pin, unsigned int vector) {
    if (pin >= 24) return;
    /* Ensure IOAPIC MMIO is mapped (may be called before ioapic_mask_all) */
    schild_map_mmio_2mb(0xFEC00000ULL);
    volatile unsigned int *ioapic = (volatile unsigned int *)0xFEC00000;
    ioapic[0x00 / 4] = 0x10 + 2 * pin;   /* IOREDTBL[pin] low */
    /* PCIe INTx is level-triggered and active-low.  Configuring the pin as
     * edge/high (vector alone) misses the already-asserted line, so the e1000e
     * IRQ never reaches the CPU on real hardware (hlt never wakes). */
    ioapic[0x10 / 4] = vector | (1u << 15) | (1u << 13);  /* level, active-low */
}

/* e1000e IRQ handler — minimal: wakes CPU for RX processing.
 * Reads and clears ICR to de-assert interrupt, sets pending flag.
 * Actual packet processing happens in the main kernel loop. */
static unsigned long long e1000e_mmio = 0;
volatile unsigned int e1000e_rx_pending = 0;  /* Set=1 when RX interrupt fires */
volatile unsigned int e1000e_irq_count = 0;   /* diagnostic: handler invocations */

void schild_e1000e_set_mmio(unsigned long long mmio) {
    e1000e_mmio = mmio;
}

__attribute__((interrupt)) void e1000e_irq_handler(void *f) {
    (void)f;
    if (e1000e_mmio == 0) return;
    e1000e_irq_count++;

    /* Read ICR (Interrupt Cause Read) at offset 0x00C0 */
    volatile unsigned int *mmio = (volatile unsigned int *)e1000e_mmio;
    unsigned int icr = mmio[0x00C0 / 4];

    /* Set pending flag if RX-related interrupt (RXT0=bit7, RXDMT0=bit4, RXO=bit6) */
    if (icr & ((1 << 7) | (1 << 4) | (1 << 6))) {
        e1000e_rx_pending = 1;
    }

    /* Clear ICR bits (write 1 to clear) — de-asserts interrupt line */
    mmio[0x00C0 / 4] = icr;

    /* LAPIC EOI */
    *(volatile unsigned int*)0xFEE000B0 = 0;
}

/* Direct IDT patch for vector 0x20 — bypass Ada IDT machinery */
void schild_idt_patch_irq0(void) {
    unsigned short *idt = (unsigned short *)0x10e8c0;
    unsigned long long handler = (unsigned long long)&schild_raw_irq_handler;
    unsigned short *entry = idt + (0x20 * 8);  /* 16 bytes per entry = 8 shorts */
    entry[0] = handler & 0xFFFF;         /* Offset[15:0] */
    entry[1] = 0x08;                     /* Segment selector (CS) */
    entry[2] = 0x8E00;                   /* IST=0 (low byte), Attr=0x8E (high byte) */
    entry[3] = (handler >> 16) & 0xFFFF; /* Offset[31:16] */
    entry[4] = (handler >> 32) & 0xFFFF; /* Offset[47:32] */
    entry[5] = (handler >> 48) & 0xFFFF; /* Offset[63:48] */
    entry[6] = 0;                        /* Reserved */
    entry[7] = 0;                        /* Reserved */
}

/* Fully initialize IDT from schild_interrupt_vectors array (Ada/C handlers).
 * Called after Ada Interrupt_Init, replaces its lidt with correct base.
 * 
 * IDT allocated in BSS (256 entries × 16 bytes = 4096 bytes) — guaranteed
 * zero-initialized by boot.S, unlike hardcoded addresses in linker gaps. */
extern void *schild_interrupt_vectors[256];

static unsigned short raw_idt[256 * 8] __attribute__((aligned(4096)));

void schild_idt_init_raw(void) {
    unsigned short *idt = raw_idt;
    
    /* Workaround: schild_interrupt_vectors[0x20] corrupted at runtime.
     * Direct references to handler functions bypass the array. */
    
    /* Declare all handlers used — interrupt attribute adds void* param */
    extern void eDE(void*), eDB(void*), eNMI(void*), eBP(void*), eOF(void*);
    extern void eBR(void*), eUD(void*), eNM(void*), eDF(void*), eTS(void*);
    extern void eNP(void*), eSS(void*), eGP(void*), ePF(void*), eMF(void*);
    extern void irq0_tmr(void*), irq1_kbd(void*);
    extern void e1000e_irq_handler(void*);
    extern void spurious_irq(void*);
    
    /* Map of handlers — direct function pointers (not via array) */
    void *handlers[256] = {0};
    handlers[0x00] = &eDE;  handlers[0x01] = &eDB;  handlers[0x02] = &eNMI;
    handlers[0x03] = &eBP;  handlers[0x04] = &eOF;  handlers[0x05] = &eBR;
    handlers[0x06] = &eUD;  handlers[0x07] = &eNM;  handlers[0x08] = &eDF;
    handlers[0x0A] = &eTS;  handlers[0x0B] = &eNP;  handlers[0x0C] = &eSS;
    handlers[0x0D] = &eGP;  handlers[0x0E] = &ePF;  handlers[0x10] = &eMF;
    handlers[0x20] = &irq0_tmr;  handlers[0x21] = &irq1_kbd;
    handlers[0x30] = &e1000e_irq_handler;  /* e1000e: vector 0x30 */
    handlers[0xFF] = &spurious_irq;        /* LAPIC spurious vector (apic_init) */
    
    for (int v = 0; v < 256; v++) {
        unsigned short *entry = idt + v * 8;
        if (handlers[v]) {
            unsigned long long h = (unsigned long long)handlers[v];
            entry[0] = h & 0xFFFF;
            entry[1] = 0x08;
            entry[2] = 0x8E00;
            entry[3] = (h >> 16) & 0xFFFF;
            entry[4] = (h >> 32) & 0xFFFF;
            entry[5] = (h >> 48) & 0xFFFF;
        } else {
            entry[0] = 0; entry[1] = 0; entry[2] = 0; entry[3] = 0;
            entry[4] = 0; entry[5] = 0; entry[6] = 0; entry[7] = 0;
        }
    }
    struct { unsigned short limit; unsigned long long base; }
        __attribute__((packed)) desc = { 4095, (unsigned long long)idt };
    __asm__ volatile("lidt %0" : : "m"(desc));
    uart_puts("[IDT] Initialized from direct handler refs (bypass array)\r\n");
}

void schild_verify_idt(void) {
    struct { unsigned short limit; unsigned long long base; }
        __attribute__((packed)) desc;
    __asm__ volatile("sidt %0" : "=m"(desc));
    if (desc.limit == 4095) {
        uart_puts("[IDT] Pre-loop IDTR OK (limit=4095)\r\n");
    } else {
        uart_puts("[IDT] Pre-loop IDTR CORRUPTED!\r\n");
    }
    unsigned short *e = (unsigned short *)desc.base + 0x20 * 8;
    /* Check each field individually */
    if (e[0] == 0) { uart_puts("[IDT] Entry 0x20 FAIL: offset[15:0] is 0\r\n"); }
    else if (e[1] != 0x0008) { uart_puts("[IDT] Entry 0x20 FAIL: selector != 0x08\r\n"); }
    else if (e[2] != 0x8E00) { uart_puts("[IDT] Entry 0x20 FAIL: attributes != 0x8E\r\n"); }
    else { uart_puts("[IDT] Entry 0x20 OK\r\n"); }
    if (e[0] != 0 && e[1] == 0x0008 && e[2] == 0x8E00) {
        uart_puts("[IDT] Pre-loop entry 0x20 OK\r\n");
    } else {
        uart_puts("[IDT] Pre-loop entry 0x20 CORRUPTED!\r\n");
    }
}

void schild_pit_init(void){unsigned short d=11932;__asm__ volatile("outb %0,%1"::"a"((unsigned char)0x36),"Nd"(0x43));__asm__ volatile("outb %0,%1"::"a"((unsigned char)(d&0xFF)),"Nd"(0x40));__asm__ volatile("outb %0,%1"::"a"((unsigned char)(d>>8)),"Nd"(0x40));}
void schild_pic_remap(void){
    /* Mask all IRQs first */
    __asm__ volatile("outb %0,%1"::"a"((unsigned char)0xFF),"Nd"(0x21));
    __asm__ volatile("outb %0,%1"::"a"((unsigned char)0xFF),"Nd"(0xA1));
    /* ICW1-ICW4 init sequence */
    __asm__("outb %0,%1"::"a"((unsigned char)0x11),"Nd"(0x20));
    __asm__("outb %0,%1"::"a"((unsigned char)0x11),"Nd"(0xA0));
    __asm__("outb %0,%1"::"a"((unsigned char)0x20),"Nd"(0x21));
    __asm__("outb %0,%1"::"a"((unsigned char)0x28),"Nd"(0xA1));
    __asm__("outb %0,%1"::"a"((unsigned char)0x04),"Nd"(0x21));
    __asm__("outb %0,%1"::"a"((unsigned char)0x02),"Nd"(0xA1));
    __asm__("outb %0,%1"::"a"((unsigned char)0x01),"Nd"(0x21));
    __asm__("outb %0,%1"::"a"((unsigned char)0x01),"Nd"(0xA1));
}
void schild_pic_unmask_irq0(void){__asm__ volatile("outb %0,%1"::"a"((unsigned char)0xFE),"Nd"(0x21));}

void schild_sti(void)  { __asm__ volatile("sti"); }
void schild_hlt(void)  { __asm__ volatile("hlt"); }
void schild_cli(void)  { __asm__ volatile("cli"); }

void *schild_interrupt_vectors[256]={[0x00]=eDE,[0x01]=eDB,[0x02]=eNMI,[0x03]=eBP,[0x04]=eOF,[0x05]=eBR,[0x06]=eUD,[0x07]=eNM,[0x08]=eDF,[0x0A]=eTS,[0x0B]=eNP,[0x0C]=eSS,[0x0D]=eGP,[0x0E]=ePF,[0x10]=eMF,[0x20]=irq0_tmr,[0x21]=irq1_kbd,};
