# Schild TCB R3 — Config Daemon thread entry point
.section .text
.global config_daemon_entry
config_daemon_entry:
    leaq    config_stack_top(%rip), %rsp
    call    config_daemon_main
    ud2

.section .bss
.align 16

/* Aliveness flag — BEFORE stack to prevent overwrite */
.globl config_alive_flag
config_alive_flag:
    .space 8

.globl config_stack_bottom
config_stack_bottom:
    .space 4096
.globl config_stack_top
config_stack_top:

.section .note.GNU-stack,"",@progbits
