/* Copyright (C) 2026 Alexander Irganov
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * Schild TCB -- child-process layout (separate VSpace demo).
 *
 * The child is a self-contained ET_EXEC linked at 0x400000, the same base the
 * root task uses -- safe because it lives in a *different* VSpace.  Code +
 * read-only data form one RX segment; writable data + BSS (which holds the
 * stack) form a separate RW segment so the ELF loader can map them with
 * different permissions.
 */
ENTRY(_child_start)
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
    . = ALIGN(0x1000);
    .data   : { *(.data*) } :rw
    .bss    : { *(.bss*) *(COMMON) } :rw
    /DISCARD/ : { *(.note.*) *(.comment) *(.eh_frame*) }
}
