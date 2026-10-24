/* Minimal seL4 Root Task — proves the full boot chain.
 * Just loops forever. seL4 schedules it, no faults = SUCCESS.
 */
.section .text
.globl _start
_start:
1:  nop
    jmp 1b

.section .note.GNU-stack,"",@progbits
