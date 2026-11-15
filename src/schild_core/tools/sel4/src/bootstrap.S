# Schild TCB — mini-bootstrap (root task as ELF-child, Phase A skeleton)
# First userspace thread; Phase B will Load_Elf(root_task.elf) + TCB_Resume.
.section .text
.global bootstrap_entry
bootstrap_entry:
    leaq    bootstrap_stack_top(%rip), %rsp
    call    bootstrap_main
    ud2

.section .bss
.align 16

/* Aliveness flag — BEFORE stack to prevent overwrite */
.globl bootstrap_alive_flag
bootstrap_alive_flag:
    .space 8

.globl bootstrap_stack_bottom
bootstrap_stack_bottom:
    .space 4096
.globl bootstrap_stack_top
bootstrap_stack_top:

.section .note.GNU-stack,"",@progbits
