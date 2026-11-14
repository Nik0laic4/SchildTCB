#!/usr/bin/env bash
# =============================================================================
# Schild TCB -- SchildFS on-disk parsing core (Schild_Fs_Core) known-answer test.
# Compiles fs_core_kat.adb against the native GNAT toolchain and verifies
# CRC32 (ISO-HDLC) + superblock/dir-entry serialization round-trips.
# Exits non-zero on mismatch.
# =============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"   # .../tools/sel4/tests
SEL4_DIR="$(cd "$HERE/.." && pwd)"      # .../tools/sel4

find_gnat_bin() {
  if command -v gnatmake >/dev/null 2>&1; then
    dirname "$(command -v gnatmake)"
  elif [ -n "${TOOL:-}" ] && [ -x "$TOOL/gnatmake" ]; then
    printf '%s\n' "$TOOL"
  else
    ls -1d "$HOME"/.local/share/alire/toolchains/gnat_native_*/bin 2>/dev/null | head -1
  fi
}

GNAT_BIN="$(find_gnat_bin)"
if [ -z "$GNAT_BIN" ]; then
  echo "ERROR: GNAT compiler (gnat_native toolchain) not found." >&2
  exit 2
fi

OBJ="$SEL4_DIR/obj/kat_fs_core"
rm -rf "$OBJ" && mkdir -p "$OBJ"

echo "GNAT: $GNAT_BIN"
(
  cd "$OBJ"
  "$GNAT_BIN/gnatmake" -gnat2022 -gnatwa -g -O0 \
      -I../../../../src/04_userland \
      -I../../../../src/03_crypto \
      -o fs_core_kat ../../tests/fs_core_kat.adb
)

"$OBJ/fs_core_kat"
