#!/usr/bin/env bash
# =============================================================================
# AES-128 known-answer test (KAT).
#
# Host-side gate: compiles Schild_Aes_Ni_Core against the native GNAT toolchain
# and runs the FIPS-197 (Appendix B + C.1) AES-128 vectors. Exits non-zero if
# any vector mismatches.
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

OBJ="$SEL4_DIR/obj/kat_aes"
rm -rf "$OBJ" && mkdir -p "$OBJ"

echo "GNAT: $GNAT_BIN"
(
  cd "$OBJ"
  "$GNAT_BIN/gnatmake" -gnat2022 -gnatwa -g -O0 \
      -I../../../../src/03_crypto \
      -o aes_kat ../../tests/aes_kat.adb
)

"$OBJ/aes_kat"
