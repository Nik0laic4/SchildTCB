/*
 * Copyright (C) 2026 Ирганов А.Н. Все права защищены.
 * Данный исходный код является объектом интеллектуальной собственности.
 * Разработано в научно-исследовательских и учебно-образовательных целях.
 * Проект имеет статус ограниченного распространения; публикация в открытых
 * репозиториях и передача третьим лицам без согласия автора не допускаются.
 */

/* Root Task startup stub — sets up stack, captures RDI (BootInfo ptr),
 * calls Ada entry point.
 * seL4 starts thread with RSP=0; we allocate a stack in .bss.
 * Linked at 0x400000 (seL4 user-space default).
 */

.section .bss
.align 16
.space 65536              /* 64KB stack: BootInfo value copy (~8KB) + demo locals */
rt_stack_top:

/* Store seL4's RDI (BootInfo frame vptr) for Ada code */
.globl rt_bootinfo_vptr
.align 8
rt_bootinfo_vptr:
    .space 8

.section .text
.globl _start
_start:
    /* Save BootInfo pointer from RDI (seL4 passes bi_frame_vptr here) */
    movq    %rdi, rt_bootinfo_vptr(%rip)

    leaq    rt_stack_top, %rsp
    call    _ada_schild_root_task

    /* Should never return */
1:  pause
    jmp     1b

.section .note.GNU-stack,"",@progbits
