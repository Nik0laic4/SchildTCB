/* Copyright (C) 2026 Alexander Irganov
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Schild TCB -- child-process entry point (separate VSpace demo).
 *
 * The child runs in its own VSpace and CSpace.  It sets up its stack (in its
 * own .bss, mapped read-write by the ELF loader) and calls child_main().
 */
.section .text
.globl _child_start
_child_start:
    adrp x0, child_stack_top
    add  sp, x0, :lo12:child_stack_top
    bl   child_main
1:  wfe
    b    1b

.section .bss
.align 16
child_stack:
    .space 16384            /* 16 KiB stack */
child_stack_top:
