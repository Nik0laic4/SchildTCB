#!/bin/bash
# =============================================================================
# Build Root Task ELF for seL4 (user-space at 0x400000)
# Called from build.sh when SEL4_PRIMARY=1
# =============================================================================
set -e
cd "$(dirname "$0")"

# Reproducible-build hardening: map the absolute build root to a relative
# prefix in debug/macro info so no host path is embedded in compiler output.
# (BUILD_ROOT must be the repository root so the private/ overlay — which lives
# at <repo>/private, not under src/ — is resolved correctly.)
BUILD_ROOT="$(cd ../../../.. && pwd)"
# Reproducible-build hardening: map the build root to a relative prefix so no
# host path is embedded in compiler output. -fdebug-prefix-map is valid for
# Ada and C; -fmacro-prefix-map is C/C++ only (gnat1 rejects it for Ada).
PREFIX_MAP_ADA=(-fdebug-prefix-map="${BUILD_ROOT}=.")
PREFIX_MAP_C=(-fdebug-prefix-map="${BUILD_ROOT}=." -fmacro-prefix-map="${BUILD_ROOT}=.")

# IOMMU (VT-d): -DSCHILD_IOMMU shifts the X86 arch invocation labels in the C
# shim (CONFIG_IOMMU inserts 3 extra labels).  Set SCHILD_IOMMU=1 when the
# kernel was built with KERNEL_IOMMU=ON.
if [ "${SCHILD_IOMMU:-0}" = "1" ] || [ "${SCHILD_IOMMU:-0}" = "ON" ]; then
  PREFIX_MAP_C+=(-DSCHILD_IOMMU=1)
fi

# Reproducible-build hardening: pin the build timestamp so __DATE__/__TIME__ and
# compiler metadata are deterministic. Defaults to the last commit timestamp.
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct 2>/dev/null || echo 0)}"
export SOURCE_DATE_EPOCH

TOOL="${TOOL:-$HOME/.local/share/alire/toolchains/gnat_native_14.2.1_06bb3def/bin}"
OBJ=obj/root_task
rm -rf "$OBJ" && mkdir -p "$OBJ"

# =============================================================================
# Two-circuit build profile: public (TCB scaffold, stub commercial modules)
# vs private (overlay real modules from private/).
# =============================================================================
PROFILE="${SCHILD_PROFILE:-public}"
OVERLAY="$OBJ/overlay"
# Stage 9.2: C runtime source for the audit bridge (schild_debug_render).
# Default is the public scaffold; the private profile overlays the real
# Schild_Debug_Render body from private/root_task/.
C_RUNTIME="src/schild_net_runtime.c"
if [ "$PROFILE" = "private" ]; then
    SAFE="$BUILD_ROOT/private/root_task"
    if [ ! -d "$SAFE" ]; then
        echo "  [RT] ERROR: private profile requires $SAFE" >&2
        exit 1
    fi
    mkdir -p "$OVERLAY"
    cp "$SAFE/schild_audit_logger.adb" "$SAFE/schild_config_daemon.adb" \
       "$SAFE/schild_boot_manager.adb" "$OVERLAY/"
    echo "  [RT] private profile: overlaying commercial modules from $SAFE (into $OVERLAY)"
    # Overlay the real Schild_Debug_Render C body: in the private profile the
    # audit bridge runs the honest Read_Event loop over the overlaid
    # Schild_Audit_Logger and fills the buffer with real log lines.
    if [ -f "$SAFE/schild_net_runtime.c" ]; then
        cp "$SAFE/schild_net_runtime.c" "$OBJ/schild_net_runtime.c"
        C_RUNTIME="$OBJ/schild_net_runtime.c"
        echo "  [RT] private profile: overlaying schild_net_runtime.c (real Schild_Debug_Render)"
    fi
else
    echo "  [RT] public profile: stub commercial modules (TCB scaffold)"
fi

echo "  [RT] Building Ada root task..."

# Ada compilation
# HMAC-SHA256 lives in ../../src/03_crypto (single source of truth); compile it
# first so its dependents (Boot Manager) can resolve the spec/ALI.
if ! "$TOOL/gcc" -c --RTS="$(pwd)/../../bare_runtime" -gnat2022 -gnatwa -gnato -gnatVa -g -O0 "${PREFIX_MAP_ADA[@]}" \
    -I"$OBJ" -Isrc -I../../src -I../../src/03_crypto \
    -o "$OBJ/schild_hmac_sha256.o" ../../src/03_crypto/schild_hmac_sha256.adb 2>&1; then
    echo "  [RT] ERROR: schild_hmac_sha256.adb"
    exit 1
fi

for src in schild_mls_policy schild_audit_logger schild_config_daemon schild_boot_manager schild_hm_model schild_launch_model schild_watchdog schild_root_task schild_sel4_syscall schild_sel4_bootinfo schild_net_server; do
    SF="src/${src}.adb"
    [ -f "$OVERLAY/${src}.adb" ] && SF="$OVERLAY/${src}.adb"
    if ! "$TOOL/gcc" -c --RTS="$(pwd)/../../bare_runtime" -gnat2022 -gnatwa -gnato -gnatVa -g -O0 "${PREFIX_MAP_ADA[@]}" \
        -I"$OBJ" -Isrc -I../../src -I../../src/03_crypto -I../../src/01_hardware -I../../src/04_userland \
        -o "$OBJ/${src}.o" "$SF" 2>&1; then
        echo "  [RT] ERROR: ${src}.adb"
        exit 1
    fi
done

# e1000e + network stack + parsers (Ring 3 NetServer) — from the core tree.
# schild_net_types is a spec-only package (compiled with its dependents).
DRV_INC="-I$OBJ -Isrc -I../../src -I../../src/01_hardware -I../../src/04_userland"
for spec in \
     ../../src/04_userland/schild_net_config \
     ../../src/schild_uart_driver \
     ../../src/01_hardware/schild_pci_scanner \
     ../../src/01_hardware/schild_e1000e \
     ../../src/01_hardware/schild_nvme \
     ../../src/04_userland/schild_arp_handler \
     ../../src/04_userland/schild_ipv4_handler \
     ../../src/04_userland/schild_tcp_handler \
     ../../src/04_userland/schild_http_server \
     ../../src/04_userland/schild_schild_fs \
     ../../src/04_userland/schild_net_stack; do
    b="$(basename "$spec")"
    if ! "$TOOL/gcc" -c --RTS="$(pwd)/../../bare_runtime" -gnat2022 -gnatwa -gnato -gnatVa -g -O0 "${PREFIX_MAP_ADA[@]}" \
        $DRV_INC -o "$OBJ/${b}.o" "${spec}.adb" 2>&1; then
        echo "  [RT] ERROR: ${b}.adb"
        exit 1
    fi
done

# C compilation
"$TOOL/gcc" -m64 -nostdlib -nostdinc -fno-builtin -std=gnu11 \
    -fno-stack-protector -mno-red-zone -ffreestanding -mgeneral-regs-only "${PREFIX_MAP_C[@]}" \
    -c -o "$OBJ/message_info.o" src/message_info.c 2>&1

"$TOOL/gcc" -m64 -nostdlib -nostdinc -fno-builtin -std=gnu11 \
    -fno-stack-protector -mno-red-zone -ffreestanding -mgeneral-regs-only "${PREFIX_MAP_C[@]}" \
    -c -o "$OBJ/schild_sel4_ipc.o" src/schild_sel4_ipc.c 2>&1

"$TOOL/gcc" -m64 -nostdlib -nostdinc -fno-builtin -std=gnu11 \
    -fno-stack-protector -mno-red-zone -ffreestanding -mgeneral-regs-only "${PREFIX_MAP_C[@]}" \
    -c -o "$OBJ/schild_net_runtime.o" "$C_RUNTIME" 2>&1

# ASM compilation
"$TOOL/as" --64 -o "$OBJ/rt_start.o" src/rt_start.S
"$TOOL/as" --64 -o "$OBJ/schild_sel4_syscalls.o" src/schild_sel4_syscalls.S
"$TOOL/as" --64 -o "$OBJ/mls_server.o" src/mls_server.S
"$TOOL/as" --64 -o "$OBJ/config_daemon.o" src/config_daemon.S
"$TOOL/as" --64 -o "$OBJ/netserver.o" src/netserver.S

# C compilation (MLS server thread)
"$TOOL/gcc" -m64 -nostdlib -nostdinc -fno-builtin -std=gnu11 \
    -fno-stack-protector -mno-red-zone -ffreestanding -mgeneral-regs-only "${PREFIX_MAP_C[@]}" \
    -c -o "$OBJ/mls_server_c.o" src/mls_server.c 2>&1

# C compilation (Config Daemon thread — R3)
"$TOOL/gcc" -m64 -nostdlib -nostdinc -fno-builtin -std=gnu11 \
    -fno-stack-protector -mno-red-zone -ffreestanding -mgeneral-regs-only "${PREFIX_MAP_C[@]}" \
    -c -o "$OBJ/config_daemon_c.o" src/config_daemon.c 2>&1

# C compilation (NetServer thread)
"$TOOL/gcc" -m64 -nostdlib -nostdinc -fno-builtin -std=gnu11 \
    -fno-stack-protector -mno-red-zone -ffreestanding -mgeneral-regs-only "${PREFIX_MAP_C[@]}" \
    -c -o "$OBJ/netserver_c.o" src/netserver.c 2>&1

# Link
"$TOOL/ld" -T src/rt_linker.ld -o root_task.elf \
    "$OBJ/rt_start.o" \
    "$OBJ/schild_hmac_sha256.o" \
    "$OBJ/schild_mls_policy.o" \
    "$OBJ/schild_audit_logger.o" \
    "$OBJ/schild_config_daemon.o" \
    "$OBJ/schild_boot_manager.o" \
    "$OBJ/schild_hm_model.o" \
    "$OBJ/schild_launch_model.o" \
    "$OBJ/schild_watchdog.o" \
    "$OBJ/schild_root_task.o" \
    "$OBJ/schild_sel4_syscall.o" \
    "$OBJ/schild_sel4_bootinfo.o" \
    "$OBJ/schild_net_server.o" \
    "$OBJ/schild_uart_driver.o" \
    "$OBJ/schild_pci_scanner.o" \
    "$OBJ/schild_e1000e.o" \
    "$OBJ/schild_nvme.o" \
    "$OBJ/schild_arp_handler.o" \
    "$OBJ/schild_ipv4_handler.o" \
    "$OBJ/schild_tcp_handler.o" \
    "$OBJ/schild_http_server.o" \
    "$OBJ/schild_schild_fs.o" \
    "$OBJ/schild_net_stack.o" \
    "$OBJ/schild_net_config.o" \
    "$OBJ/schild_sel4_syscalls.o" \
    "$OBJ/mls_server.o" \
    "$OBJ/mls_server_c.o" \
    "$OBJ/config_daemon.o" \
    "$OBJ/config_daemon_c.o" \
    "$OBJ/netserver.o" \
    "$OBJ/netserver_c.o" \
    "$OBJ/message_info.o" \
    "$OBJ/schild_sel4_ipc.o" \
    "$OBJ/schild_net_runtime.o" 2>&1

echo "  [RT] root_task.elf: $(wc -c < root_task.elf) bytes"

# Post-build path sanitization: strip host-absolute paths from root-task artifacts.
bash ../../scripts/sanitize_paths.sh || true
