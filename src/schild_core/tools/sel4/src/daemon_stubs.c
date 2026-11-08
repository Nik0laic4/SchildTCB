/* H87: daemon-only link stubs (compiled into daemon ELFs, NOT root_task.elf).
 *
 * 1. rt_bootinfo_vptr — daemons are spawned by the root task via IPC, not booted
 *    by the bootloader, so they have no boot-info pointer. message_info.c
 *    references this symbol; the stub satisfies the linker (a daemon never calls
 *    schild_get_bootinfo). root_task.elf defines the real symbol in rt_start.S.
 *
 * 2. schild_audit_render — the real Ada renderer lives in schild_net_server.adb
 *    (NetServer-only /debug bridge). Other daemons link schild_net_runtime.o but
 *    never call schild_debug_render, so a no-op stub satisfies the linker.
 */
unsigned long rt_bootinfo_vptr = 0;

void schild_audit_render(void *buffer, int max_len, int *actual_len) {
    (void)buffer;
    (void)max_len;
    if (actual_len != 0) {
        *actual_len = 0;
    }
}
