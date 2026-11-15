/*
 * Schild TCB — mini-bootstrap startup stub (root task as ELF-child, Phase B).
 * Same shape as rt_start.S: saves RDI (BootInfo ptr), sets up a stack, calls
 * the Ada entry (_ada_schild_bootstrap). Linked at 0x400000.
 */

.section .bss
.align 16
.space 65536              /* 64KB stack */
bootstrap_stack_top:

/* Store seL4's RDI (BootInfo frame vptr) for the Ada/C code */
.globl rt_bootinfo_vptr
.align 8
rt_bootinfo_vptr:
    .space 8

.section .text
.globl _start
_start:
    movq    %rdi, rt_bootinfo_vptr(%rip)
    leaq    bootstrap_stack_top(%rip), %rsp
    call    _ada_schild_bootstrap

    /* Should never return */
1:  pause
    jmp     1b

.section .note.GNU-stack,"",@progbits
