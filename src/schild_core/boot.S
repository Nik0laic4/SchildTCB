/*
 * Copyright (C) 2026 Ирганов А.Н. Все права защищены.
 * Данный исходный код является объектом интеллектуальной собственности.
 * Разработано в научно-исследовательских и учебно-образовательных целях.
 * Проект имеет статус ограниченного распространения; публикация в открытых
 * репозиториях и передача третьим лицам без согласия автора не допускаются.
 */

.code32
/* Schild TCB Stage 1 — Multiboot2 → x86_64 Long Mode → Ada kernel.
 * Target: Lenovo ThinkPad T580 (i7-8550U, Kaby Lake R, UEFI). */

.section .multiboot
.align 8
multiboot_header:
    .long 0xE85250D6              /* Multiboot2 magic                     */
    .long 0x00000000              /* Architecture: x86 Protected Mode      */
    .long multiboot_header_end - multiboot_header
    .long -(0xE85250D6 + 0x00000000 + (multiboot_header_end - multiboot_header))

    /* Framebuffer request tag (type 5) — T580 native resolution */
    .align 8
fb_req_start:
    .word 5                       /* Type: framebuffer info               */
    .word 1                       /* Flags: bit 0 = don't care if exact   */
    .long fb_req_end - fb_req_start
    .long 0                       /* Width  — any (GRUB picks via gfxmode) */
    .long 0                       /* Height — any                        */
    .long 0                       /* Depth  — any                        */
fb_req_end:

    /* NOTE: no EFI boot-services tag. boot.S is 32-bit code, so the kernel
     * must be entered in 32-bit protected mode (Multiboot2 i386 default).
     * The EFI boot-services tag made UEFI GRUB enter the kernel in 64-bit
     * long mode, where the 32-bit code faults (#GP at `mov %eax, pml4_table`
     * = opcode A3, moffs64 vs moffs32). GRUB still provides the framebuffer
     * via the type-8 tag before exiting boot services. */

    /* NOTE: no relocatable-header tag. The kernel is linked at 1MB with
     * absolute addresses and no ELF relocations, so GRUB must load it at the
     * link address. A relocatable tag makes UEFI GRUB load it elsewhere,
     * which breaks every absolute symbol reference (e.g. pml4_table) and
     * triple-faults in setup_identity_paging. */

    /* End tag (type 0, size 8) */
    .align 8
end_tag:
    .word 0
    .word 0
    .long 8
multiboot_header_end:

.section .bss
.align 4096
stack_bottom:
    .skip 65536                   /* 64 KiB kernel stack                 */
stack_top:
.align 4096
pml4_table:
    .skip 4096
.align 4096
pdpt_table:
    .skip 4096
.align 4096
pd_table:
    .skip 4096

.align 4096
pd_table2:                             /* PD for PDPT[3] (3-4 GB): FB + APIC */
    .skip 4096

/* Framebuffer pointer storage (filled by GRUB2) */
.global fb_addr, fb_width, fb_height, fb_bpp, fb_pitch
.global pd_table2                        /* Page table for MMIO mapping */
fb_addr:
    .skip 8
fb_width:
    .skip 4
fb_height:
    .skip 4
fb_bpp:
    .skip 4
fb_pitch:
    .skip 4

.section .text
.global _start
.code32
_start:
    cli
    cld

    /* Zero BSS section (GRUB2 does NOT do this for Multiboot2) */
    mov $stack_bottom, %edi       /* BSS start                         */
    mov $kernel_end, %ecx
    sub %edi, %ecx                /* BSS size in bytes                 */
    shr $2, %ecx                  /* convert to dwords                 */
    xor %eax, %eax
    rep stosl                     /* zero entire BSS                   */

    mov %ebx, multiboot_magic    /* GRUB passes Multiboot2 info pointer in EBX */
    mov $stack_top, %esp

    /* Diagnostic: CapsLock LED = _start reached (32-bit) */
    mov $0x04, %al
    call set_leds32

    call check_cpuid
    call check_long_mode
    call setup_identity_paging

    /* Diagnostic: NumLock LED = 0-4 GB identity map completed */
    mov $0x02, %al
    call set_leds32

    /* Parse Multiboot2 info: locate framebuffer tag */
    call parse_multiboot2_fb

    /* Map framebuffer + APIC MMIO into page tables */
    call setup_fb_apic_paging

    mov %cr4, %eax
    or  $0x00000020, %eax
    mov %eax, %cr4

    mov $0xC0000080, %ecx
    rdmsr
    or  $0x00000100, %eax
    wrmsr

    mov %cr0, %eax
    or  $0x80000000, %eax
    mov %eax, %cr0

    lgdt gdt64_descriptor
    ljmp $0x08, $long_mode_entry

/* --- CPUID --- */
check_cpuid:
    push %eax; push %ecx
    pushfl; pop %eax; mov %eax, %ecx
    xor $0x00200000, %eax
    push %eax; popfl; pushfl; pop %eax
    xor %ecx, %eax
    jz no_cpuid
    pop %ecx; pop %eax; ret
no_cpuid:
    mov $msg_no_cpuid, %esi; call print_string32; cli; hlt
1: jmp 1b

/* --- Long Mode --- */
check_long_mode:
    push %eax; push %ecx; push %edx
    mov $0x80000000, %eax; cpuid
    cmp $0x80000001, %eax; jb no_long_mode
    mov $0x80000001, %eax; cpuid
    test $0x20000000, %edx; jz no_long_mode
    pop %edx; pop %ecx; pop %eax; ret
no_long_mode:
    mov $msg_no_long, %esi; call print_string32; cli; hlt
1: jmp 1b

/* --- Multiboot2 Framebuffer Parser --- */
/* Scans tags sequentially: type 8 (framebuffer) provides 64-bit linear address */
/* CRITICAL: On UEFI (T580), framebuffer may be mapped above 4 GiB — */
/*           we MUST read all 64 bits of the address!                   */
parse_multiboot2_fb:
    push %eax; push %ecx; push %edx; push %esi; push %edi
    mov $0, %eax                /* fb_addr = 0 (not found)               */
    mov %eax, fb_addr
    mov %eax, fb_addr+4         /* high 32 bits = 0                      */
    mov %eax, fb_width
    mov %eax, fb_height
    mov %eax, fb_bpp
    mov %eax, fb_pitch

    /* Multiboot2 info starts with: total_size (4 bytes), reserved (4 bytes) */
    mov multiboot_magic, %esi
    cmp $0, %esi
    je  fb_parse_done

    mov 0(%esi), %ecx           /* total_size                            */
    add $8, %esi                /* skip header                           */

fb_tag_loop:
    cmp $0, %ecx
    jle fb_parse_done
    cmp $8, %ecx
    jl  fb_parse_done

    cmpw $8, 0(%esi)            /* tag type = framebuffer?               */
    jne fb_next_tag

    /* Found framebuffer tag (type 8):
       offset 8:  u64 framebuffer_addr
       offset 16: u32 framebuffer_pitch
       offset 20: u32 framebuffer_width
       offset 24: u32 framebuffer_height
       offset 28: u8  framebuffer_bpp
       offset 29: u8  framebuffer_type  (0=indexed, 1=RGB, 2=EGA text)
    */
    mov  8(%esi), %eax          /* fb_addr low 32 bits                   */
    mov  %eax, fb_addr
    mov 12(%esi), %eax          /* fb_addr high 32 bits (UEFI!)          */
    mov  %eax, fb_addr+4
    mov 16(%esi), %eax          /* pitch                                 */
    mov  %eax, fb_pitch
    mov 20(%esi), %eax          /* width                                 */
    mov  %eax, fb_width
    mov 24(%esi), %eax          /* height                                */
    mov  %eax, fb_height
    movzbl 28(%esi), %eax       /* bpp (u8 → zero-extend)               */
    mov  %eax, fb_bpp
    movzbl 29(%esi), %eax       /* fb_type: 0=indexed,1=RGB,2=text      */
    cmp  $2, %al                /* EGA text mode → no framebuffer!       */
    je   fb_text_mode

    mov $msg_fb_found, %esi
    call print_string32
    jmp fb_parse_done

fb_text_mode:
    /* GRUB fell back to text mode — framebuffer NOT available */
    mov $0, %eax
    mov %eax, fb_addr
    mov %eax, fb_addr+4
    mov $msg_fb_text, %esi
    call print_string32
    jmp fb_parse_done

fb_next_tag:
    /* type ≠ framebuffer: skip to next tag (8-byte aligned) */
    mov 4(%esi), %eax           /* tag size                              */
    add $7, %eax                /* round up to 8-byte alignment          */
    and $0xFFFFFFF8, %eax
    add %eax, %esi              /* next tag                              */
    sub %eax, %ecx              /* remaining bytes                       */
    jmp fb_tag_loop

fb_parse_done:
    pop %edi; pop %esi; pop %edx; pop %ecx; pop %eax
    ret

/* --- Identity Paging --- */
setup_identity_paging:
    push %eax; push %ecx; push %edx; push %edi
    mov $pml4_table, %edi; mov $(4096*3/4), %ecx; xor %eax, %eax; rep stosl
    mov $pdpt_table, %eax; or $0x03, %eax; mov %eax, pml4_table
    mov $pd_table, %eax; or $0x03, %eax; mov %eax, pdpt_table

    /* Fill PD with 32 entries -> identity-map 0-64 MB (2 MB huge pages) */
    /* This covers Schild TCB kernel + GRUB modules + Multiboot2 info struct */
    mov $pd_table, %edi
    mov $0x00000083, %eax           /* phys=0, Present+Writable+Huge        */
    mov $32, %ecx                   /* 32 entries x 2MB = 64MB              */
1:  mov %eax, (%edi)
    add $0x00200000, %eax           /* next 2 MB physical address           */
    add $8, %edi                    /* next PD entry                        */
    loop 1b

    mov $pml4_table, %eax; mov %eax, %cr3
    pop %edi; pop %edx; pop %ecx; pop %eax; ret

/* --- Setup FB + APIC Paging --- */
/* Maps framebuffer and APIC MMIO as 2 MB huge pages.                  */
/* FB address from Multiboot2 tag (fb_addr, fb_addr+4).                */
/* APIC at 0xFEE00000 (always below 4 GB).                             */
setup_fb_apic_paging:
    push %eax; push %ecx; push %edx; push %esi; push %ebx

    /* ---- PDPT[3] = pd_table2 (covers 3-4 GB: FB + APIC region) ---- */
    mov $pd_table2, %eax
    or  $0x03, %eax               /* present + writable                  */
    mov %eax, pdpt_table + 3*8    /* PDPT[3] = pd_table2                */

    /* ---- Map Framebuffer (if found and below 4 GB) ---- */
    mov fb_addr+4, %eax           /* high 32 bits                        */
    cmp $0, %eax
    jne fb_above_4g               /* FB above 4 GB → map in 64-bit mode  */

    mov fb_addr, %eax             /* low 32 bits                         */
    cmp $0, %eax
    je  fb_map_done               /* FB not found, skip                  */
    cmp $0xC0000000, %eax
    jb  fb_map_done               /* below 3 GB: remap in 64-bit mode    */

    /* PD index = (fb_addr >> 21) & 0x1FF, within PDPT[3] region        */
    /* fb_addr in [0xC0000000, 0xFFFFFFFF] → subtract 0xC0000000 first  */
    mov %eax, %esi
    sub $0xC0000000, %esi          /* offset within PDPT[3] region       */
    shr $21, %esi                  /* PD index                           */
    shl $3, %esi                   /* × 8 (entry size)                   */

    /* Map enough 2 MB huge pages to cover the WHOLE framebuffer
     * (pitch x height bytes), not just the first 2 MB. A FHD 32-bpp
     * framebuffer is ~8 MB = 4 pages; mapping one page left the
     * console with only the top ~13 lines visible.                   */
    mov %eax, %edx
    and $0xFFE00000, %edx          /* %edx = 2 MB-aligned phys base      */
    mov %eax, %ecx
    and $0x1FFFFF, %ecx            /* %ecx = fb offset within 2 MB page  */
    mov fb_pitch, %eax
    imull fb_height, %eax          /* %eax = framebuffer size in bytes   */
    add %ecx, %eax                 /* + offset from the page start       */
    add $0x1FFFFF, %eax            /* round up to a page boundary        */
    shr $21, %eax                  /* %eax = number of 2 MB pages        */

    /* Cap the page count so we never write past pd_table2 (512 entries) */
    mov %esi, %ecx
    shr $3, %ecx                   /* %ecx = starting PD index           */
    mov $512, %ebx
    sub %ecx, %ebx                 /* %ebx = entries remaining           */
    cmp %ebx, %eax
    jbe 1f
    mov %ebx, %eax                 /* clamp                               */
1:
    mov %eax, %ecx                 /* %ecx = loop counter (pages)        */
    test %ecx, %ecx
    jz 2f
3:
    mov %edx, %ebx
    or  $0x1083, %ebx              /* huge+writable+present+PAT(WC)     */
    mov %ebx, pd_table2(%esi)      /* set PD entry                       */
    add $0x00200000, %edx          /* next 2 MB physical address         */
    add $8, %esi                   /* next PD entry                      */
    dec %ecx
    jnz 3b
2:

    mov $msg_fb_mapped, %esi
    call print_string32
    jmp fb_map_done

fb_above_4g:
    mov $msg_fb_above_4g, %esi
    call print_string32

fb_map_done:

    /* ---- Map APIC at 0xFEE00000 ---- */
    /* PD index = (0xFEE00000 - 0xC0000000) >> 21 = 0x3EE >> 21 = 0x1F7 */
    mov $0xFEE00000, %eax
    sub $0xC0000000, %eax
    shr $21, %eax
    shl $3, %eax                   /* × 8 (entry size)                   */
    mov $0xFEE00083, %ecx          /* 0xFEE00000 | 0x83                   */
    mov %ecx, pd_table2(%eax)      /* set PD entry                       */

    mov $msg_apic_mapped, %esi
    call print_string32

    pop %ebx; pop %esi; pop %edx; pop %ecx; pop %eax
    ret

/* --- Set keyboard LEDs (32-bit): AL = LED byte (CapsLock=4, NumLock=2) --- */
set_leds32:
    push %edx; push %ecx; push %ebx; push %eax
    mov %al, %cl                 /* save LED byte */
    mov $0x64, %dx
    mov $100000, %ebx            /* bounded wait: never hang the boot */
1:  in %dx, %al; test $0x02, %al; jz 3f    /* input buffer empty? */
    dec %ebx; jnz 1b
    jmp 4f                       /* timeout: give up */
3:  mov $0x60, %dx
    mov $0xED, %al; out %al, %dx
    mov $0x64, %dx
    mov $100000, %ebx
2:  in %dx, %al; test $0x02, %al; jz 5f
    dec %ebx; jnz 2b
    jmp 4f
5:  mov $0x60, %dx
    mov %cl, %al; out %al, %dx
4:  pop %eax; pop %ebx; pop %ecx; pop %edx
    ret

/* --- 32-bit UART --- */
print_string32:
    push %eax; push %edx; push %esi
    mov $0x3F8, %edx
.loop32:
    lodsb; cmp $0, %al; je .done32
.wait32:
    add $5, %edx; in %dx, %al; test $0x20, %al; jz .wait32
    sub $5, %edx; out %al, %dx; jmp .loop32
.done32:
    pop %esi; pop %edx; pop %eax; ret

/* ========== 64-bit Long Mode ========== */
.code64
.global long_mode_entry
long_mode_entry:
    mov $0x10, %ax
    mov %ax, %ds; mov %ax, %es; mov %ax, %fs; mov %ax, %gs; mov %ax, %ss
    movabs $stack_top, %rsp

    /* Diagnostic: CapsLock+NumLock = 64-bit long mode reached */
    mov $0x06, %edi
    call schild_kbd_leds

    call uart_init64

    /* Mask all PIC interrupts.
     * CRITICAL: GRUB2/Multiboot2 may leave the PIT running with PIC unmasked.
     * Without this, the first 'sti' instruction triggers a pending IRQ0
     * on the default vector (0x08 = #DF), causing triple-fault → reboot.
     * Solution: mask both PICs immediately on entry to 64-bit mode,
     * before any interrupt controller initialization. */
    mov $0xFF, %al
    out %al, $0x21        /* Mask master PIC (IRQ0-7) */
    out %al, $0xA1        /* Mask slave PIC (IRQ8-15) */

    /* === Enable FPU/SSE (required by GNAT Ada code) === */
    /* GNAT generates pxor/movaps for zero-initialization of records.
     * Without CR4.OSFXSR, these cause #UD (Invalid Opcode).
     * CR0.TS and CR0.EM must be cleared to avoid #NM (Device Not Available). */
    finit                          /* initialize x87 FPU                 */
    mov %cr0, %rax
    and $~(1<<3), %eax            /* clear CR0.TS (no task switch)      */
    and $~(1<<2), %eax            /* clear CR0.EM (don't emulate)       */
    or  $(1<<1), %eax             /* set   CR0.MP (monitor coprocessor) */
    mov %rax, %cr0
    mov %cr4, %rax
    or  $(1<<9), %eax             /* set   CR4.OSFXSR (enable SSE)      */
    or  $(1<<10), %eax            /* set   CR4.OSXMMEXCPT (SIMD exc)    */
    mov %rax, %cr4

    /* Framebuffer test: draw a white pixel at top-left corner if FB found */
    movabs $fb_addr, %rax
    mov (%rax), %rax
    cmp $0, %rax
    je  fb_skip
    /* FB found: log it */
    mov $msg_fb_available, %esi
    call print_string64
fb_skip:

    /* Remap an above-4GB GOP framebuffer into the PDPT[3] window at
     * 0xFE000000. boot.S maps the framebuffer only below 4 GB (32-bit mode);
     * a UEFI GOP framebuffer is usually above 4 GB. */
    movabs $fb_addr, %rax
    mov (%rax), %rax             /* full 64-bit fb address                */
    test %rax, %rax
    jz  fb_no_remap              /* no framebuffer                        */
    movabs $0xC0000000, %rcx
    cmp %rcx, %rax
    jb  fb_remap                 /* below 0xC0000000 -> remap             */
    movabs $0x100000000, %rcx
    cmp %rcx, %rax
    jb  fb_no_remap              /* in [0xC0000000, 4 GB) -> already mapped*/
fb_remap:
    movabs $0xFFFFFFFFFFE00000, %rcx
    and  %rcx, %rax              /* align to 2 MB                          */
    or   $0x1083, %rax           /* huge+writable+present+PAT(WC)       */
    movabs $pd_table2, %rdi
    mov  $0x1F0, %rsi            /* PD index for 0xFE000000 in PDPT[3]    */
    shl  $3, %rsi
    mov  %rax, (%rdi, %rsi)      /* pd_table2[496] -> fb physical          */
    movabs $fb_addr, %rax
    movl $0xFE000000, (%rax)     /* rewrite fb_addr low to virtual window */
    movl $0, 4(%rax)             /* ... and high 32 bits to 0              */
fb_no_remap:

    mov $msg_long_ok, %esi
    call print_string64

    movabs $multiboot_magic, %rax
    mov (%rax), %edi             /* arg1: Multiboot2 info pointer      */
    movabs $fb_addr, %rax
    mov (%rax), %rsi             /* arg2: fb_addr                      */
    movabs $fb_width, %rax
    mov (%rax), %edx             /* arg3: fb_width                     */
    movabs $fb_height, %rax
    mov (%rax), %ecx             /* arg4: fb_height                    */
    movabs $fb_pitch, %rax
    mov (%rax), %r8d             /* arg5: fb_pitch                     */
    movabs $fb_bpp, %rax
    mov (%rax), %r9d             /* arg6: fb_bpp                       */
    call schild_kernel_entry
    cli; hlt
1: jmp 1b

/* --- UART Init (64-bit) --- */
uart_init64:
    mov $0x3F9, %dx; xor %al, %al; out %al, %dx
    mov $0x3FB, %dx; mov $0x80, %al; out %al, %dx
    mov $0x3F8, %dx; mov $0x03, %al; out %al, %dx
    mov $0x3F9, %dx; xor %al, %al; out %al, %dx
    mov $0x3FB, %dx; mov $0x03, %al; out %al, %dx
    mov $0x3FA, %dx; mov $0xC7, %al; out %al, %dx
    ret

/* --- 64-bit UART printer (byte saved in %cl before THRE) --- */
print_string64:
    push %rax; push %rdx; push %rsi; push %rcx
.loop64:
    lodsb
    cmp $0, %al
    je .done64
    mov %al, %cl
.wait64:
    mov $0x3FD, %dx
    in %dx, %al
    test $0x20, %al
    jz .wait64
    mov %cl, %al
    mov $0x3F8, %dx
    out %al, %dx
    jmp .loop64
.done64:
    mov $0x3F8, %dx; mov $0x0D, %al; out %al, %dx
.wait_cr:
    mov $0x3FD, %dx; in %dx, %al; test $0x20, %al; jz .wait_cr
    mov $0x0A, %al; mov $0x3F8, %dx; out %al, %dx
    pop %rcx; pop %rsi; pop %rdx; pop %rax; ret

/* ========== Minimal 64-bit interrupt handler ========== */
.global schild_raw_irq_handler
schild_raw_irq_handler:
    /* Save XMM registers (Ada code uses SSE) */
    sub $512, %rsp
    movaps %xmm0,  0x000(%rsp)
    movaps %xmm1,  0x010(%rsp)
    movaps %xmm2,  0x020(%rsp)
    movaps %xmm3,  0x030(%rsp)
    movaps %xmm4,  0x040(%rsp)
    movaps %xmm5,  0x050(%rsp)
    movaps %xmm6,  0x060(%rsp)
    movaps %xmm7,  0x070(%rsp)
    movaps %xmm8,  0x080(%rsp)
    movaps %xmm9,  0x090(%rsp)
    movaps %xmm10, 0x0A0(%rsp)
    movaps %xmm11, 0x0B0(%rsp)
    movaps %xmm12, 0x0C0(%rsp)
    movaps %xmm13, 0x0D0(%rsp)
    movaps %xmm14, 0x0E0(%rsp)
    movaps %xmm15, 0x0F0(%rsp)
    push %rax
    push %rbx
    movabs $0xFEE000B0, %rbx
    movl $0, (%rbx)       /* APIC EOI */
    pop %rbx
    pop %rax
    /* Restore XMM */
    movaps 0x000(%rsp), %xmm0
    movaps 0x010(%rsp), %xmm1
    movaps 0x020(%rsp), %xmm2
    movaps 0x030(%rsp), %xmm3
    movaps 0x040(%rsp), %xmm4
    movaps 0x050(%rsp), %xmm5
    movaps 0x060(%rsp), %xmm6
    movaps 0x070(%rsp), %xmm7
    movaps 0x080(%rsp), %xmm8
    movaps 0x090(%rsp), %xmm9
    movaps 0x0A0(%rsp), %xmm10
    movaps 0x0B0(%rsp), %xmm11
    movaps 0x0C0(%rsp), %xmm12
    movaps 0x0D0(%rsp), %xmm13
    movaps 0x0E0(%rsp), %xmm14
    movaps 0x0F0(%rsp), %xmm15
    add $512, %rsp
    iretq

.section .data
.align 8
multiboot_magic:
    .quad 0

.align 16
gdt64:
gdt64_null: .quad 0
gdt64_code: .quad 0x0020980000000000
gdt64_data: .quad 0x0000920000000000
gdt64_end:
gdt64_descriptor:
    .word gdt64_end - gdt64_null - 1
    .quad gdt64

.section .rodata
msg_no_cpuid:
    .asciz "[FATAL] CPUID not supported\r\n"
msg_no_long:
    .asciz "[FATAL] Long Mode not available\r\n"
msg_long_ok:
    .asciz "[BOOT] Entered x86_64 Long Mode, UART initialized"
msg_fb_found:
    .asciz "[BOOT] Framebuffer found via Multiboot2 tag\r\n"
msg_fb_available:
    .asciz "[BOOT] FB address received: "
msg_fb_text:
    .asciz "[BOOT] FB: text mode only (no graphics framebuffer)\r\n"
msg_fb_mapped:
    .asciz "[BOOT] FB: mapped into page tables (2MB huge page)\r\n"
msg_fb_above_4g:
    .asciz "[BOOT] FB: above 4GB, map deferred to 64-bit mode\r\n"
msg_apic_mapped:
    .asciz "[BOOT] APIC: 0xFEE00000 mapped (2MB huge page)\r\n"
msg_author:
    .asciz "Schild TCB v0.5.0-pre — microkernel OS. (c) 2025-2026 Ирганов А.Н.\r\n"


.section .note.GNU-stack,"",@progbits
