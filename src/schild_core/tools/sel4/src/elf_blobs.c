/* Schild TCB — daemon-ELF blob accessors (H87).
 * These symbols are produced by `ld -r -b binary <daemon>.bin` and embedded only
 * in root_task.elf (NOT in the daemon ELFs). This file is compiled/linked ONLY
 * into root_task.elf, so the accessors never pollute the daemon ELF link. */
typedef unsigned long long u64;

extern unsigned char _binary_obj_root_task_fs_daemon_elf_start[];
extern unsigned char _binary_obj_root_task_fs_daemon_elf_end[];

u64 schild_fs_daemon_elf_start(void) {
    return (u64)_binary_obj_root_task_fs_daemon_elf_start;
}
u64 schild_fs_daemon_elf_size(void) {
    return (u64)(_binary_obj_root_task_fs_daemon_elf_end -
                 _binary_obj_root_task_fs_daemon_elf_start);
}

extern unsigned char _binary_obj_root_task_mls_daemon_elf_start[];
extern unsigned char _binary_obj_root_task_mls_daemon_elf_end[];

u64 schild_mls_daemon_elf_start(void) {
    return (u64)_binary_obj_root_task_mls_daemon_elf_start;
}
u64 schild_mls_daemon_elf_size(void) {
    return (u64)(_binary_obj_root_task_mls_daemon_elf_end -
                 _binary_obj_root_task_mls_daemon_elf_start);
}

extern unsigned char _binary_obj_root_task_config_daemon_elf_start[];
extern unsigned char _binary_obj_root_task_config_daemon_elf_end[];

u64 schild_config_daemon_elf_start(void) {
    return (u64)_binary_obj_root_task_config_daemon_elf_start;
}
u64 schild_config_daemon_elf_size(void) {
    return (u64)(_binary_obj_root_task_config_daemon_elf_end -
                 _binary_obj_root_task_config_daemon_elf_start);
}
