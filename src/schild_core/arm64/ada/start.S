/* Copyright (C) 2026 Alexander Irganov
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Schild TCB -- AArch64 bare-metal entry point (qemu-system-aarch64 -M virt).
 *
 * QEMU jumps here at the ELF entry address with the MMU and caches off.  The
 * CPU is already in a valid exception level; all we need before calling Ada is
 * a stack pointer, so we point SP at a 16 KiB area reserved in .bss.
 */
.section .text
.globl _start
_start:
    adrp x0, stack_top
    add  sp, x0, :lo12:stack_top
    bl   _ada_hello_world
1:  wfe
    b    1b

.section .bss
.align 16
stack:
    .space 16384            /* 16 KiB stack */
stack_top:
