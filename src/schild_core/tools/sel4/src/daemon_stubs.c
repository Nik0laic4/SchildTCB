/* H87: daemon-only link stubs (compiled into daemon ELFs, NOT root_task.elf).
 *
 * rt_bootinfo_vptr — daemons are spawned by the root task via IPC, not booted
 * by the bootloader, so they have no boot-info pointer. message_info.c
 * references this symbol; the stub satisfies the linker (a daemon never calls
 * schild_get_bootinfo). root_task.elf defines the real symbol in rt_start.S.
 */
unsigned long rt_bootinfo_vptr = 0;
