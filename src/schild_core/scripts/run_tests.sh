#!/usr/bin/env bash
# Schild TCB QEMU smoke test.
#
# Boots the built image in QEMU and asserts the expected success markers in the
# serial log. Exits non-zero if any marker is missing or a panic/fault pattern
# appears.
#
# Usage:
#   bash scripts/run_tests.sh               # build + boot (seL4 primary, canonical)
#   SKIP_BUILD=1 bash scripts/run_tests.sh  # reuse existing artifacts
#
# Env:
#   SEL4_PRIMARY   1 = seL4 + Ada Root Task (default), 0 = standalone Ring 0 kernel
#   SCHILD_PROFILE public|private (default public)
#   TOOL           GNAT toolchain bin dir (default alire native 14.2.1)
#   QEMU_TIMEOUT   boot timeout in seconds (default 30)
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

SEL4_PRIMARY="${SEL4_PRIMARY:-1}"
SCHILD_PROFILE="${SCHILD_PROFILE:-public}"
TOOL="${TOOL:-$HOME/.local/share/alire/toolchains/gnat_native_14.2.1_06bb3def/bin}"
QEMU_TIMEOUT="${QEMU_TIMEOUT:-60}"

# IOMMU (VT-d): boot under q35 + intel-iommu.  Set IOMMU=1 together with
# KERNEL_IOMMU=ON (kernel) + KERNEL_IOMMU=ON (root task build).
#
# NOTE: EXPERIMENTAL / FLAKY.  KernelVerificationBuild=OFF (required by IOMMU)
# makes the MCS sporadic scheduling-context path hang non-deterministically
# (observed at the Config Daemon's sporadic SC, never at round-robin SCs).
# This is an upstream seL4 x86_64 MCS+IOMMU limitation, not a root-task bug.
QEMU_MACHINE_FLAGS=""
if [ "${IOMMU:-0}" = "1" ]; then
  QEMU_MACHINE_FLAGS="-machine q35 -device intel-iommu"
  QEMU_TIMEOUT=60   # IOMMU context-table setup slows boot
fi

SERIAL_LOG="$(mktemp /tmp/schild_serial.XXXXXX.log)"

if [ "$SEL4_PRIMARY" = "1" ]; then
  ISO="sel4_primary.iso"
  BOOT_DONE="==== Root Task ready ===="
else
  ISO="schild_os.iso"
  BOOT_DONE="[NET] Stack ready. Listening on :80"
fi

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  TOOL="$TOOL" SCHILD_PROFILE="$SCHILD_PROFILE" SEL4_PRIMARY="$SEL4_PRIMARY" ./build.sh
fi

[ -f "$ISO" ] || { echo "ERROR: $ISO not found (build first)" >&2; exit 1; }

# Standalone kernel: SMP (AP bring-up) and the SchildFS write-path test need
# -smp and an NVMe device carrying the SchildFS GPT-gap structures at
# LBA 2016..2047 (see mkschildfs.py).
EXTRA_FLAGS=""
if [ "$SEL4_PRIMARY" = "0" ]; then
  NVME_IMG="${NVME_IMG:-/tmp/schild_nvme.img}"
  python3 mkschildfs.py /tmp/schildfs_gap.img >/dev/null 2>&1
  dd if=/dev/zero of="$NVME_IMG" bs=512 count=4096 status=none
  dd if=/tmp/schildfs_gap.img of="$NVME_IMG" bs=512 seek=2016 conv=notrunc status=none
  EXTRA_FLAGS="-smp 8 -drive file=$NVME_IMG,if=none,id=nvme0 -device nvme,serial=SCHILD0001,drive=nvme0"
fi
# seL4 (W7): NVMe controller + GPT-gap drive image carrying the SchildFS
# structures at LBA 2016..2047 (see mkschildfs.py).
if [ "$SEL4_PRIMARY" = "1" ]; then
  NVME_IMG="${NVME_IMG:-/tmp/schild_nvme.img}"
  python3 mkschildfs.py /tmp/schildfs_gap.img >/dev/null 2>&1
  dd if=/dev/zero of="$NVME_IMG" bs=512 count=4096 status=none
  dd if=/tmp/schildfs_gap.img of="$NVME_IMG" bs=512 seek=2016 conv=notrunc status=none
  EXTRA_FLAGS="-drive file=$NVME_IMG,if=none,id=nvme0 -device nvme,serial=SCHILD0001,drive=nvme0"
fi

echo "Booting $ISO in QEMU (timeout ${QEMU_TIMEOUT}s) ..."
timeout "$QEMU_TIMEOUT" qemu-system-x86_64 $QEMU_MACHINE_FLAGS -boot d -cdrom "$ISO" -m 512M -cpu max \
  $EXTRA_FLAGS -display none -serial "file:$SERIAL_LOG" &
QPID=$!

# Poll for the boot-complete marker and stop QEMU as soon as it appears.
for _ in $(seq 1 "$QEMU_TIMEOUT"); do
  if grep -qF "$BOOT_DONE" "$SERIAL_LOG" 2>/dev/null; then
    break
  fi
  sleep 1
done
kill "$QPID" 2>/dev/null || true
wait "$QPID" 2>/dev/null || true

if [ "$SEL4_PRIMARY" = "1" ]; then
  MARKERS=(
    "[S7] T4 PASS"
    "[S7.2] T8 PASS"
    "[S7.2] T9 PASS"
    "[S7.7] MLS Server: OK"
    "[S8.2] NetServer VSpace: OK"
    "[S8.3] e1000e IRQ: OK"
    "[S8.1D] Reply status: 0000000000000000"
    "[S8.4] tx_frame echo: 0x000000000000005A"
    "[CONTAINMENT] injecting fault into NetServer"
    "[FAULT] Caught fault"
    "[CONTAINMENT] core alive after fault"
    "[FAULT] Caught MLS fault"
    "[CONTAINMENT] MLS server contained"
    "[FAULT] Caught Config fault"
    "[CONTAINMENT] Config Daemon contained"
    "[HM] MLS server fault -> STOP"
    "[TIMEOUT] Caught budget overrun"
    "[NVME] Init OK — queues ready"
    "[NVFS] Read-back VERIFY OK"
    "==== Root Task ready ===="
  )
else
  MARKERS=(
    "[BOOT] Entered x86_64 Long Mode"
    "[E1000E] Init OK"
    "All APs started"
    "[AUDIT] Test5 MLS Terminate: PASS"
    "[NVFS] Read-back VERIFY OK"
    "[NET] Stack ready. Listening on :80"
  )
fi

FAIL_PATTERNS=("Panic" "#GP" "General Protection" "[FAIL" "unhandled fault")

fail=0
for m in "${MARKERS[@]}"; do
  if grep -qF "$m" "$SERIAL_LOG"; then
    echo "PASS  $m"
  else
    echo "FAIL  $m"
    fail=1
  fi
done
for p in "${FAIL_PATTERNS[@]}"; do
  if grep -qF "$p" "$SERIAL_LOG"; then
    echo "FAIL  unexpected pattern in log: $p"
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "--- serial log ($SERIAL_LOG) ---"
  cat "$SERIAL_LOG"
  exit 1
fi

echo "All checks passed. Log: $SERIAL_LOG"
