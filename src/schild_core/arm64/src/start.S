/* Minimal seL4 root-task entry (AArch64, EL0).
 * Sets up a stack and calls main(). */
.section .text
.global _start
_start:
    adrp x0, stack_top
    add  sp, x0, :lo12:stack_top
    bl   main
    b    .            /* halt if main returns */

.section .bss
.align 16
stack:
    .space 8192
stack_top:
