/* Schild TCB — mini-bootstrap (root task as ELF-child, Phase A skeleton).
 *
 * First userspace thread.  Phase A is only a stub: signal aliveness then halt.
 * Phase B will retype a PML4 + page tables and Load_Elf(root_task.elf) via the
 * existing loader, then TCB_Resume the root task (ROOT_TASK_ELF_CHILD_DESIGN.md).
 */
void bootstrap_main(void) {
    extern char bootstrap_alive_flag;
    bootstrap_alive_flag = 0x01;  /* aliveness marker */
    for (;;) __asm__ volatile("pause");
}
