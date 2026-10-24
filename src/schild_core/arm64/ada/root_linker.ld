/* Copyright (C) 2026 Alexander Irganov
 * SPDX-License-Identifier: GPL-2.0-only
 *
 * seL4 AArch64 root-task layout.  The ELF is loaded by the seL4 elfloader at
 * its linked virtual address; 0x60000000 matches the existing arm64 C root-task
 * experiment (arm64/linker.ld).  The exact load address is re-confirmed when
 * the root task is run under the seL4 elfloader (pending on this machine).
 */
ENTRY(_start)
PHDRS
{
    rx PT_LOAD FLAGS(5);   /* R-X: code + read-only data */
    rw PT_LOAD FLAGS(6);   /* RW-: writable data + BSS */
}
SECTIONS
{
    . = 0x60000000;
    .text   : { *(.text*) } :rx
    .rodata : { *(.rodata*) } :rx
    . = ALIGN(0x10000);
    .data   : { *(.data*) } :rw
    .bss    : { *(.bss*) *(COMMON) } :rw
    /DISCARD/ : { *(.note.*) *(.comment) *(.eh_frame*) }
}
