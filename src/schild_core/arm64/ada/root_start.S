/* Copyright (C) 2026 Alexander Irganov
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Schild TCB -- seL4 AArch64 root-task entry point.
 *
 * seL4 drops the root task into user space (EL0) with the BootInfo pointer in
 * x0 and the IPC buffer pointer in x1, and with an uninitialised stack.  We set
 * up a 16 KiB stack in .bss and jump to the Ada main procedure.  (BootInfo/IPC
 * capture is intentionally deferred: the current root task only uses the debug
 * console, which needs no boot info.)
 */
.section .text
.globl _start
_start:
    adrp x0, stack_top
    add  sp, x0, :lo12:stack_top
    bl   _ada_schild_arm_root_task
1:  wfe
    b    1b

.section .bss
.align 16
stack:
    .space 16384            /* 16 KiB stack */
stack_top:
