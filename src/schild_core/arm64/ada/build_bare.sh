#!/usr/bin/env bash
# =============================================================================
# Schild TCB -- build + run the AArch64 bare-metal runtime smoke test in QEMU.
#
# Proves the Zero-Footprint-Profile runtime (bare_runtime) compiles and runs on
# ARM64: hello_world.adb is built with the cross-GNAT toolchain against
# --RTS=bare_runtime, linked at a fixed address, and booted by
# qemu-system-aarch64 "-M virt".  A successful run prints the banner over the
# emulated PL011 UART.
#
# Usage:
#   ./build_bare.sh          # build and run in QEMU (10 s timeout)
#   RUN=0 ./build_bare.sh    # build only (no QEMU)
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
        echo "[bare] ERROR: tool not found: $tool" >&2
        exit 1
    fi
done

rm -rf obj && mkdir -p obj

# 1. Compile the Ada closure (hello_world + UART + the needed runtime units).
#    -fno-pie/-fno-pic: bare-metal image at a fixed address (no GOT/relocs).
"$GNATMAKE" -c --RTS="$RTS" -gnat2022 -gnatwa -O0 -g \
    -fno-pie -fno-pic -I. -D obj hello_world.adb

# 2. Assemble the entry point.
"$GCC" -c -fno-pie -fno-pic -o obj/start.o start.S

# 3. Compile the GNAT runtime stubs (__gnat_rcheck_*, libc, unwind).
"$GCC" -c -ffreestanding -nostdlib -nostdinc -fno-builtin \
    -fno-pie -fno-pic -fno-stack-protector -O2 \
    -o obj/runtime_stubs.o runtime_stubs.c

# 4. Link: start.o first (it owns _start), then every other object in the closure.
mapfile -t OBJS < <(find obj -name '*.o' ! -name 'start.o' | sort)
"$LD" -T linker_bare.ld -o hello.elf obj/start.o "${OBJS[@]}"

echo "[bare] hello.elf: $(wc -c < hello.elf) bytes"

if [ "${RUN:-1}" = "1" ]; then
    echo "[bare] booting in QEMU ..."
    # -serial file: writes the PL011 console directly to a file (no stdio
    # buffering), so the output is captured reliably even when the script's own
    # stdout is redirected.  -no-reboot halts after the (infinite) Ada loop,
    # and `timeout` reaps the process.
    SERIAL_LOG="qemu_serial.log"
    rm -f "$SERIAL_LOG"
    set +e
    timeout "${TIMEOUT:-10}" qemu-system-aarch64 \
        -M virt -cpu cortex-a53 -m 128M -no-reboot \
        -display none -monitor none -serial "file:$SERIAL_LOG" \
        -kernel hello.elf
    rc=$?
    set -e
    echo "[bare] --- PL011 UART output ---"
    cat "$SERIAL_LOG"
    rm -f "$SERIAL_LOG"
    # 124 = killed by `timeout` after the guest reached its halt loop: expected.
    if [ "$rc" -ne 0 ] && [ "$rc" -ne 124 ]; then
        echo "[bare] QEMU exited with status $rc" >&2
        exit "$rc"
    fi
fi
