/* Copyright (C) 2026 Alexander Irganov
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Bare-metal layout for qemu-system-aarch64 "-M virt -kernel".
 * The virt machine's RAM starts at 0x40000000 and -kernel loads the image
 * there; the PL011 console is at 0x09000000 (device MMIO, not in this image).
 */
ENTRY(_start)
PHDRS
{
    rx PT_LOAD FLAGS(5);   /* R-X: code + read-only data */
    rw PT_LOAD FLAGS(6);   /* RW-: writable data + BSS */
}
SECTIONS
{
    . = 0x40000000;
    .text   : { *(.text*) } :rx
    .rodata : { *(.rodata*) } :rx
    . = ALIGN(0x10000);
    .data   : { *(.data*) } :rw
    .bss    : { *(.bss*) *(COMMON) } :rw
    /DISCARD/ : { *(.note.*) *(.comment) *(.eh_frame*) }
}
