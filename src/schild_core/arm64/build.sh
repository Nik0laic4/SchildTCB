#!/usr/bin/env bash
# Build a minimal seL4 AArch64 root task (C) for QEMU (qemu-arm-virt).
set -euo pipefail
cd "$(dirname "$0")"

CROSS=aarch64-linux-gnu-

"${CROSS}gcc" -c -o obj/start.o   src/start.S
"${CROSS}gcc" -c -o obj/debug_io.o src/debug_io.c -ffreestanding -O2
"${CROSS}gcc" -c -o obj/main.o     src/main.c     -ffreestanding -O2
"${CROSS}ld"  -T linker.ld -o root_task.elf obj/start.o obj/debug_io.o obj/main.o

echo "Built: root_task.elf"
