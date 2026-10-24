/* Minimal linker script for an seL4 AArch64 root task (user-space ELF). */
ENTRY(_start)
SECTIONS
{
    . = 0x60000000;
    .text   : { *(.text*) }
    .rodata : { *(.rodata*) }
    .data   : { *(.data*) }
    .bss    : { *(.bss*) *(COMMON) }
}
