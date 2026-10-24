# Schild TCB Stage 8.1D — NetServer thread entry point
.section .text
.global netserver_entry
netserver_entry:
    leaq    netserver_stack_top(%rip), %rsp
    call    netserver_main
    ud2

.section .bss
.align 16
.globl netserver_stack_bottom
netserver_stack_bottom:
    .space 8192
.globl netserver_stack_top
netserver_stack_top:

.section .note.GNU-stack,"",@progbits
