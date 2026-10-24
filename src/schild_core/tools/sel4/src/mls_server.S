# Schild TCB Stage 7.5 — MLS Server Thread entry point
.section .text
.global mls_server_entry
mls_server_entry:
    leaq    mls_stack_top(%rip), %rsp
    call    mls_server_main
    ud2

.section .bss
.align 16

/* Aliveness flag — BEFORE stack to prevent overwrite (H3 fix) */
.globl mls_alive_flag
mls_alive_flag:
    .space 8

.globl mls_stack_bottom
mls_stack_bottom:
    .space 4096
.globl mls_stack_top
mls_stack_top:

.section .note.GNU-stack,"",@progbits
