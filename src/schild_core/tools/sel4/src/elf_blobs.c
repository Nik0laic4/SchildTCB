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

extern unsigned char _binary_obj_root_task_netserver_elf_start[];
extern unsigned char _binary_obj_root_task_netserver_elf_end[];

u64 schild_netserver_elf_start(void) {
    return (u64)_binary_obj_root_task_netserver_elf_start;
}
u64 schild_netserver_elf_size(void) {
    return (u64)(_binary_obj_root_task_netserver_elf_end -
                 _binary_obj_root_task_netserver_elf_start);
}

/* M20: build-time self-test switch for the Ada root task. Returns 1 only when
 * SCHILD_SELFTEST is defined (the QEMU containment/timeout self-tests); a
 * production build returns 0 and the root task skips the fault-injection
 * driver entirely.  Lives here (not in schild_sel4_ipc.c) so the daemon ELFs,
 * which also link schild_sel4_ipc.o, keep their layout unchanged. */
u64 schild_selftest_enabled(void) {
#ifdef SCHILD_SELFTEST
    return 1;
#else
    return 0;
#endif
}
