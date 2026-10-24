#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build-test"
mkdir -p "$BUILD_DIR"

cd "$ROOT_DIR"

gcc -m32 -nostdlib -nostartfiles -ffreestanding -c boot.S -o "$BUILD_DIR/boot.o"
ld -m elf_i386 -T linker.ld -o "$BUILD_DIR/kernel.bin" "$BUILD_DIR/boot.o" "$ROOT_DIR/schild_kernel_entry.o"

printf 'Built %s\n' "$BUILD_DIR/kernel.bin"
