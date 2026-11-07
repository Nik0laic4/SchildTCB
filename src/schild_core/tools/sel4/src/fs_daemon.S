# Schild TCB — FS Daemon thread entry point (audit H65/H86).
# Pattern: netserver.S + mls_server.S. Alive flag BEFORE stack (H3 fix).
.section .text
.global fs_daemon_entry
fs_daemon_entry:
    leaq    fs_daemon_stack_top(%rip), %rsp
    andq    $-16, %rsp
    call    fs_daemon_main
    ud2

.section .bss
.align 16

/* Aliveness flag — BEFORE stack to prevent overwrite (H3 fix).
 * 0 = not started, 0x01 = Recv loop running, 0xFF = error (no ep/reply). */
.globl fs_daemon_alive_flag
fs_daemon_alive_flag:
    .space 8

.globl fs_daemon_stack_bottom
fs_daemon_stack_bottom:
    .space 8192
.globl fs_daemon_stack_top
fs_daemon_stack_top:

.section .note.GNU-stack,"",@progbits
