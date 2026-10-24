/* Copyright (C) 2026 Alexander Irganov
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * seL4 AArch64 root-task layout.  The ELF is loaded by the seL4 elfloader at
 * its linked virtual address.  seL4 AArch64 root tasks are linked at 0x400000
 * (the aarch64-linux-gnu default text segment) with entry `_sel4_start`, the
 * same convention the sel4runtime root task uses.
 */
ENTRY(_sel4_start)
PHDRS
{
    rx PT_LOAD FLAGS(5);   /* R-X: code + read-only data */
    rw PT_LOAD FLAGS(6);   /* RW-: writable data + BSS */
}
SECTIONS
{
    . = 0x400000;
    .text   : { *(.text*) } :rx
    .rodata : { *(.rodata*) } :rx
    . = ALIGN(0x10000);
    .data   : { *(.data*) } :rw
    .bss    : { *(.bss*) *(COMMON) } :rw
    /DISCARD/ : { *(.note.*) *(.comment) *(.eh_frame*) }
}
