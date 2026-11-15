/* Schild TCB — mini-bootstrap (root task as ELF-child).
 *
 * The Ada body (schild_bootstrap.adb) is the loader: it reads BootInfo, retypes
 * a PML4 + page tables, Load_Elf(root_task.elf) and TCB_Resume's the root task.
 * This C file only exposes the embedded blob's start/size accessors.
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
