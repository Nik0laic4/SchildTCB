/* Copyright (C) 2026 Alexander Irganov
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Schild TCB -- AArch64 bare-metal entry point (qemu-system-aarch64 -M virt).
 * Same as start.S but for the virtio-net probe main.  Sets up a 16 KiB stack
 * and jumps to the Ada main procedure.
 */
.section .text
.globl _start
_start:
    adrp x0, stack_top
    add  sp, x0, :lo12:stack_top
    bl   _ada_virtio_probe
1:  wfe
    b    1b

.section .bss
.align 16
stack:
    .space 16384            /* 16 KiB stack */
stack_top:
