#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL_IMAGE="$ROOT_DIR/build-test/kernel.bin"

if [[ ! -f "$KERNEL_IMAGE" ]]; then
  echo "Kernel image not found: $KERNEL_IMAGE" >&2
  exit 1
fi

qemu-system-i386 -display none -serial stdio -kernel "$KERNEL_IMAGE"
