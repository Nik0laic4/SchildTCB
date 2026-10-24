#!/usr/bin/env bash
# =============================================================================
# Schild TCB -- build + run the AArch64 bare-metal virtio-net probe in QEMU.
#
# Builds virtio_probe.adb (with the Virtio_MMIO driver and the PL011 UART)
# against --RTS=bare_runtime, links it at the bare-metal load address, and boots
# it in qemu-system-aarch64 "-M virt" with a virtio-net device.  A successful
# run prints the device MAC address over the emulated PL011 UART.
#
# Usage:
#   ./build_virtio.sh         # build and run in QEMU (10 s timeout)
#   RUN=0 ./build_virtio.sh   # build only (no QEMU)
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

RTS="$(cd ../../bare_runtime && pwd)"
PREFIX="${CROSS:-aarch64-linux-gnu-}"

GNATMAKE="${PREFIX}gnatmake-14"
GCC="${PREFIX}gcc-14"
LD="${PREFIX}ld"

for tool in "$GNATMAKE" "$GCC" "$LD"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[virtio] ERROR: tool not found: $tool" >&2
        exit 1
    fi
done

rm -rf obj && mkdir -p obj

# 1. Compile the Ada closure (virtio_probe + Virtio_MMIO + UART + runtime units).
"$GNATMAKE" -c --RTS="$RTS" -gnat2022 -gnatwa -O0 -g \
    -fno-pie -fno-pic -I. -D obj virtio_probe.adb

# 2. Assemble the entry point.
"$GCC" -c -fno-pie -fno-pic -o obj/virtio_start.o virtio_start.S

# 3. Compile the GNAT runtime stubs (__gnat_rcheck_*, libc, unwind).
"$GCC" -c -ffreestanding -nostdlib -nostdinc -fno-builtin \
    -fno-pie -fno-pic -fno-stack-protector -O2 \
    -o obj/runtime_stubs.o runtime_stubs.c

# 4. Link: virtio_start.o first (it owns _start), then the rest of the closure.
mapfile -t OBJS < <(find obj -name '*.o' ! -name 'virtio_start.o' | sort)
"$LD" -T linker_bare.ld -o virtio_probe.elf obj/virtio_start.o "${OBJS[@]}"

echo "[virtio] virtio_probe.elf: $(wc -c < virtio_probe.elf) bytes"

if [ "${RUN:-1}" = "1" ]; then
    echo "[virtio] booting in QEMU ..."
    SERIAL_LOG="qemu_serial.log"
    rm -f "$SERIAL_LOG"
    set +e
    timeout "${TIMEOUT:-10}" qemu-system-aarch64 \
        -M virt -cpu cortex-a53 -m 128M -no-reboot \
        -display none -monitor none -serial "file:$SERIAL_LOG" \
        -netdev user,id=n0 \
        -device virtio-net-device,netdev=n0,mac=52:54:00:12:34:56 \
        -kernel virtio_probe.elf
    rc=$?
    set -e
    echo "[virtio] --- PL011 UART output ---"
    cat "$SERIAL_LOG"
    rm -f "$SERIAL_LOG"
    # 124 = killed by `timeout` after the guest reached its halt loop: expected.
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ]; then
        echo "[virtio] QEMU exited with status $rc" >&2
        exit "$rc"
    fi
fi
