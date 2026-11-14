#!/usr/bin/env bash
# =============================================================================
# Schild TCB -- host-side ABI unit test for the seL4 msgInfo encoding (AS6/C4).
#
# seam_abi_test.c verifies the msgInfo bit layout (label/extraCaps/capsUnwrapped
# /length) round-trips losslessly and the length field is capped at
# seL4_MsgMaxLength (120).  QEMU-free, runs in milliseconds (CI job "seam-abi").
#
# Usage:
#   ./run_seam_abi.sh
# =============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"   # .../tools/sel4/tests
SEL4_DIR="$(cd "$HERE/.." && pwd)"      # .../tools/sel4

CC="${CC:-gcc}"
OBJ="$SEL4_DIR/obj/seam_abi"
rm -rf "$OBJ" && mkdir -p "$OBJ"

echo "[seam-abi] compile (host gcc) ..."
"$CC" -O2 -Wall -Wextra -std=gnu11 -o "$OBJ/seam_abi_test" "$HERE/seam_abi_test.c"

echo "[seam-abi] run ..."
"$OBJ/seam_abi_test"
