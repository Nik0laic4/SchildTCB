/* H87: audit-render stub for daemons that do NOT own the /debug bridge.
 *
 * schild_audit_render — the real Ada renderer lives in schild_net_server.adb
 * (NetServer-only /debug bridge). The FS/MLS/Config daemons link
 * schild_net_runtime.o but never call schild_debug_render, so this no-op
 * satisfies the linker. The NetServer links the real one instead (it does NOT
 * link this stub).
 */
void schild_audit_render(void *buffer, int max_len, int *actual_len) {
    (void)buffer;
    (void)max_len;
    if (actual_len != 0) {
        *actual_len = 0;
    }
}
