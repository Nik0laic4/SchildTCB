#!/bin/bash
set -e
cd "$(dirname "$0")"

# Reproducible-build hardening: map the absolute build root to a relative
# prefix in debug/macro info so no host path is embedded in compiler output.
BUILD_ROOT="$(cd ../.. && pwd)"
# Reproducible-build hardening: map the build root to a relative prefix so no
# host path is embedded in compiler output. -fdebug-prefix-map is valid for
# Ada and C; -fmacro-prefix-map is C/C++ only (gnat1 rejects it for Ada).
PREFIX_MAP_ADA=(-fdebug-prefix-map="${BUILD_ROOT}=.")
PREFIX_MAP_C=(-fdebug-prefix-map="${BUILD_ROOT}=." -fmacro-prefix-map="${BUILD_ROOT}=.")

# Reproducible-build hardening: pin the build timestamp so __DATE__/__TIME__ and
# compiler metadata are deterministic. Defaults to the last commit timestamp.
SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct 2>/dev/null || echo 0)}"
export SOURCE_DATE_EPOCH

TOOL="${TOOL:-$HOME/.local/share/alire/toolchains/gnat_native_14.2.1_06bb3def/bin}"
# Fall back to any installed gnat_native toolchain if the pinned version is
# absent (e.g. on CI where `alr toolchain --select gnat_native` may install a
# different release).
if [ ! -x "$TOOL/gcc" ]; then
   TOOL="$(ls -1d "$HOME"/.local/share/alire/toolchains/gnat_native_*/bin 2>/dev/null | head -1)"
fi
RTS="$(pwd)/bare_runtime"
O=obj/development
rm -rf "$O" && mkdir -p "$O"

# NOTE: the two-circuit SCHILD_PROFILE overlay for the seL4 root-task daemons
# (Audit Logger / Config Daemon / Boot Manager) lives in tools/sel4/build_rt.sh;
# the standalone kernel has no private overlay.

# === seL4 microkernel path (default: bundled in tools/sel4/) ===
SEL4_KERNEL="${SEL4_KERNEL_PATH:-tools/sel4/kernel.elf}"
SEL4_ENABLE="${ENABLE_SEL4:-0}"

echo "=== Ada (direct gcc) ==="
if [ "$SEL4_ENABLE" = "1" ]; then
   echo "  (seL4: enabled — kernel at $SEL4_KERNEL)"
fi
# === Network identity (SCHILD_IP) ===
# A generated override spec (build/gen/) lets two QEMU instances boot with
# distinct static IPv4 addresses; the default lives in
# src/04_userland/schild_net_config.ads.
GEN="build/gen"
rm -rf "$GEN" && mkdir -p "$GEN"
GEN_INC="-I$GEN"
if [ -n "${SCHILD_IP:-}" ]; then
   IFS='.' read -r IP_A IP_B IP_C IP_D <<< "$SCHILD_IP"
   IP_HEX=$(printf '16#%02X%02X_%02X%02X#' "${IP_A:-0}" "${IP_B:-0}" "${IP_C:-0}" "${IP_D:-0}")
   cat > "$GEN/schild_net_config.ads" <<EOF
with Interfaces; use Interfaces;
package Schild_Net_Config is
   pragma Elaborate_Body;
   Our_IP : constant Unsigned_32 := $IP_HEX;  -- $SCHILD_IP
end Schild_Net_Config;
EOF
   echo "  (net: SCHILD_IP=$SCHILD_IP -> $IP_HEX)"
fi
ADA_DIRS="src src/01_hardware src/02_security src/03_crypto src/04_userland"
errors=0
for d in $ADA_DIRS; do
  for f in "$d"/*.adb; do
    [ -f "$f" ] || continue
    base=$(basename "$f" .adb)
    # R6 (TCB pruning): planned-but-unintegrated modules are excluded by
    # default. ENABLE_UNWIRED=1 builds the full scaffold.
    if [ "${ENABLE_UNWIRED:-0}" != "1" ]; then
       case "$base" in
         schild_sgx_manager|schild_tme_manager|schild_mmap_parser|schild_net_queue) continue ;;
       esac
    fi
    "$TOOL/gcc" -c --RTS="$RTS" -gnat2022 -gnatwa -gnato -gnatVa -g -O0 "${PREFIX_MAP_ADA[@]}" \
      $GEN_INC -I"$O" -Isrc -Isrc/01_hardware -Isrc/02_security -Isrc/03_crypto -Isrc/04_userland \
      -o "$O/${base}.o" "$f" >"$O/${base}.log" 2>&1
    if [ $? -ne 0 ]; then
       echo "  ERROR: $f"
       cat "$O/${base}.log"
       errors=$((errors+1))
    fi
  done
done
echo "  Ada: $(ls $O/*.o 2>/dev/null | wc -l) objects, $errors errors"
if [ $errors -gt 0 ]; then
   echo "  ERROR: $errors Ada unit(s) failed to compile — aborting build." >&2
   exit 1
fi

echo "=== C ==="
CFLAGS=(-m64 -nostdlib -nostdinc -fno-builtin -fno-stack-protector -mno-red-zone -ffreestanding -mgeneral-regs-only "${PREFIX_MAP_C[@]}")

# Include seL4 headers when enabled
if [ "$SEL4_ENABLE" = "1" ]; then
   CFLAGS+=(-DENABLE_SEL4 -Isrc)
fi

"$TOOL/gcc" "${CFLAGS[@]}" -c -o "$O/runtime_stubs.o" src/runtime_stubs.c -Wno-unused-parameter
"$TOOL/gcc" "${CFLAGS[@]}" -c -o "$O/interrupt_handlers.o" src/interrupt_handlers.c -Wno-unused-parameter
"$TOOL/gcc" "${CFLAGS[@]}" -c -o "$O/schild_sel4_loader.o" src/schild_sel4_loader.c -Wno-unused-parameter
"$TOOL/gcc" "${CFLAGS[@]}" -c -o "$O/schild_sel4_boot.o" src/schild_sel4_boot.c -Wno-unused-parameter

echo "=== ASM ==="
"$TOOL/as" --64 -o "$O/boot.o" boot.S
"$TOOL/as" --64 -o "$O/smp_trampoline.o" src/01_hardware/smp_trampoline.S

echo "=== Link ==="
"$TOOL/gcc" -nostdlib -T linker.ld -z noexecstack -z now -o schild_os.elf "$O"/*.o 2>&1
echo "  -> $(wc -c < schild_os.elf) bytes"

# === ISO image with optional seL4 module ===
mkdir -p build/iso/boot/grub
cp schild_os.elf build/iso/boot/

if [ "$SEL4_ENABLE" = "1" ] && [ -f "$SEL4_KERNEL" ]; then
   cp "$SEL4_KERNEL" build/iso/boot/sel4_kernel.elf
   echo "  seL4: $(wc -c < "$SEL4_KERNEL") bytes copied to ISO"
   # Root task module (optional but recommended)
   RT_ELF="tools/sel4/root_task.elf"
   if [ -f "$RT_ELF" ]; then
      cp "$RT_ELF" build/iso/boot/root_task.elf
      echo "  root_task: $(wc -c < "$RT_ELF") bytes copied to ISO"
   fi
fi

# Build grub.cfg — seL4 module only when enabled AND file exists
cat > build/iso/boot/grub/grub.cfg << 'GRUB'
insmod efi_gop
set gfxmode=auto
set timeout=0
menuentry "Schild TCB" {
    multiboot2 /boot/schild_os.elf
GRUB
if [ "$SEL4_ENABLE" = "1" ] && [ -f "$SEL4_KERNEL" ]; then
   echo '    module2 /boot/sel4_kernel.elf' >> build/iso/boot/grub/grub.cfg
   if [ -f "$RT_ELF" ]; then
      echo '    module2 /boot/root_task.elf' >> build/iso/boot/grub/grub.cfg
   fi
fi
cat >> build/iso/boot/grub/grub.cfg << 'GRUB'
    boot;
}
GRUB

grub-mkrescue -o schild_os.iso build/iso 2>&1 | tail -1
echo "Done: schild_os.elf + schild_os.iso"

# ================================================================
# SEL4_PRIMARY mode: seL4 as Multiboot2 kernel, root_task as module
# ================================================================
if [ "${SEL4_PRIMARY:-0}" = "1" ]; then
   echo ""
   echo "=== seL4 PRIMARY MODE ==="
   if [ ! -f "$SEL4_KERNEL" ]; then
      echo "  ERROR: seL4 kernel not found at $SEL4_KERNEL"
      exit 1
   fi

   # kernel.elf is built by scripts/build_sel4_kernel.sh. The legacy ELF
   # PT_LOAD gap patch is NOT applied anymore (it broke boot — see the
   # Stage 8.0 recipe in docs/technical/CHANGELOG.md).

   # Build Ada root task from source (user-space at 0x400000)
   echo "  Building Root Task..."
   TOOL="$TOOL" SCHILD_IOMMU="${KERNEL_IOMMU:-0}" bash tools/sel4/build_rt.sh 2>&1 | grep -v 'warning:' | tail -2
   RT_ELF="tools/sel4/root_task.elf"
   if [ ! -f "$RT_ELF" ]; then
      echo "  ERROR: root task build failed"
      exit 1
   fi

   rm -rf build/sel4_iso/boot/grub
   mkdir -p build/sel4_iso/boot/grub
   cp "$SEL4_KERNEL" build/sel4_iso/boot/sel4_kernel.elf
   cp "$RT_ELF" build/sel4_iso/boot/root_task.elf
   cat > build/sel4_iso/boot/grub/grub.cfg << 'GRUBEND'
insmod efi_gop
set gfxmode=auto
set timeout=0
menuentry "seL4 + Ada Root Task" {
    multiboot2 /boot/sel4_kernel.elf
    module2 /boot/root_task.elf
    boot;
}
GRUBEND
   grub-mkrescue -o sel4_primary.iso build/sel4_iso 2>&1 | tail -1
   echo "Done: sel4_primary.iso (seL4 kernel + Ada Root Task)"
fi

# Post-build path sanitization: strip host-absolute paths from compiler artifacts.
bash scripts/sanitize_paths.sh || true
