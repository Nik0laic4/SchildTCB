ENTRY(_start)

OUTPUT_FORMAT(elf64-x86-64)
OUTPUT_ARCH(i386:x86-64)

SECTIONS
{
    /* Kernel is loaded at physical address 1 MB */
    . = 1M;

    /* Multiboot2 header (first 8 KB of the file) + code */
    .text BLOCK(4K) : ALIGN(4K)
    {
        *(.multiboot)
        *(.text .text.*)
    }

    /* Read-only data */
    .rodata BLOCK(4K) : ALIGN(4K)
    {
        *(.rodata .rodata.*)
    }

    /* Initialized data (including the 64-bit GDT in boot.S) */
    .data BLOCK(4K) : ALIGN(4K)
    {
        *(.data .data.*)
    }

    /* BSS: stack, page tables, uninitialized data */
    .bss BLOCK(4K) : ALIGN(4K)
    {
        *(COMMON)
        *(.bss .bss.*)
    }

    /* Kernel-end marker for the memory allocator */
    kernel_end = .;
}