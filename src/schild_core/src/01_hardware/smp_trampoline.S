/* Schild TCB SMP Trampoline — position-independent AP boot code
 * Relies on being copied to 0x8000; all absolute addresses
 * are computed as (label - smp_trampoline_start + 0x8000).
 * Data slots filled by BSP before INIT-SIPI-SIPI.
 */

.section .text.trampoline, "ax"
.global smp_trampoline_start, smp_trampoline_end
.code16

smp_trampoline_start:
    cli
    cld
    mov $0x800, %ax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %ss
    mov $0x1000, %sp

    /* Load 32-bit GDT — offset is relative to DS (0x800→base 0x8000) */
    lgdt (gdt32_ptr - smp_trampoline_start)

    /* Enable protected mode */
    mov %cr0, %eax
    or $1, %eax
    mov %eax, %cr0

    /* Far jump to 32-bit code */
    ljmpl $0x08, $(tramp_32 - smp_trampoline_start + 0x8000)

.code32
tramp_32:
    mov $0x10, %ax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %fs
    mov %ax, %gs
    mov %ax, %ss

    /* PAE + PGE */
    mov %cr4, %eax
    or $(1 << 5 | 1 << 7), %eax
    mov %eax, %cr4

    /* Load PML4 (low 32 bits from slot) */
    movl (pml4_slot - smp_trampoline_start + 0x8000), %eax
    mov %eax, %cr3

    /* Enable Long Mode */
    mov $0xC0000080, %ecx
    rdmsr
    or $(1 << 8), %eax
    wrmsr

    /* Enable paging */
    mov %cr0, %eax
    or $(1 << 31), %eax
    mov %eax, %cr0

    /* Load 64-bit GDT */
    lgdt (gdt64_ptr - smp_trampoline_start + 0x8000)

    /* Far jump to 64-bit code */
    ljmpl $0x08, $(tramp_64 - smp_trampoline_start + 0x8000)

.code64
tramp_64:
    mov $0x10, %ax
    mov %ax, %ds
    mov %ax, %es
    mov %ax, %fs
    mov %ax, %gs
    mov %ax, %ss

    /* Load stack and call Ada entry */
    movq (stack_slot - smp_trampoline_start + 0x8000), %rsp
    movq (entry_slot - smp_trampoline_start + 0x8000), %rax
    call *%rax

1:  hlt; jmp 1b

/* ===== GDTs ===== */
.align 16
gdt32:
    .quad 0
    .quad 0x00CF9A000000FFFF
    .quad 0x00CF92000000FFFF
gdt32_ptr:
    .word gdt32_ptr - gdt32 - 1
    .long (gdt32 - smp_trampoline_start + 0x8000)

.align 16
gdt64:
    .quad 0
    .quad 0x00AF9A000000FFFF
    .quad 0x00AF92000000FFFF
gdt64_ptr:
    .word gdt64_ptr - gdt64 - 1
    .long (gdt64 - smp_trampoline_start + 0x8000)

/* ===== Data slots (filled at runtime by BSP) ===== */
.align 8
.global tramp_pml4_slot
tramp_pml4_slot:
pml4_slot:  .quad 0
.align 8
.global tramp_stack_slot
tramp_stack_slot:
stack_slot: .quad 0
.align 4
.global tramp_cpu_id_slot
tramp_cpu_id_slot:
cpu_id_slot: .long 0
.align 8
.global tramp_entry_slot
tramp_entry_slot:
entry_slot: .quad 0

smp_trampoline_end:

.section .note.GNU-stack,"",@progbits
