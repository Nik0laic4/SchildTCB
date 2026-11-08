/* Schild TCB — daemon ELF linker script (H87).
 * Each Ring-3 daemon (mls_server / config_daemon / netserver / fs_daemon) is
 * linked as its own ET_EXEC ELF with separate .text (RX), .rodata (R),
 * .data/.bss (RW), so an OOB write in one daemon corrupts only its own .bss.
 * Mirrors the ARM64 child_linker.ld; the root-task equivalent is rt_linker.ld.
 */
SECTIONS {
    . = 0x400000;
    .text   : { *(.text) *(.text.*) }
    .rodata : { *(.rodata) *(.rodata.*) }
    . = ALIGN(0x1000);
    .data   : { *(.data) *(.data.*) }
    .bss    : { *(.bss) *(.bss.*) *(COMMON) }
    /DISCARD/ : { *(.note.*) *(.comment) *(.eh_frame) }
}
