/* Schild TCB — mini-bootstrap (root task as ELF-child, Phase A skeleton).
 *
 * First userspace thread.  Phase A is only a stub: signal aliveness then halt.
 * Phase B will retype a PML4 + page tables and Load_Elf(root_task.elf) via the
 * existing loader, then TCB_Resume the root task (ROOT_TASK_ELF_CHILD_DESIGN.md).
 */

/* Embedded root_task.elf blob (ld -r -b binary) — Phase B Load_Elf input. */
extern unsigned char _binary_root_task_elf_start[];
extern unsigned char _binary_root_task_elf_end[];

unsigned long bootstrap_root_task_elf_start(void) {
    return (unsigned long)_binary_root_task_elf_start;
}

unsigned long bootstrap_root_task_elf_size(void) {
    return (unsigned long)(_binary_root_task_elf_end -
                           _binary_root_task_elf_start);
}

void bootstrap_main(void) {
    extern char bootstrap_alive_flag;
    bootstrap_alive_flag = 0x01;  /* aliveness marker */
    for (;;) __asm__ volatile("pause");
}
