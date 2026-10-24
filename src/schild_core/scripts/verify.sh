#!/usr/bin/env bash
# Schild TCB SPARK formal-verification gate.
# Proves the Level-4 root-task daemons (verify.gpr) with GNATprove and fails
# on any unproved verification condition. This is the reproducible source of
# the "SPARK Level 4" claim.
#
# Tool discovery order:
#   1. gnatprove on PATH
#   2. $GNATPROVE
#   3. Alire release (~/.local/share/alire/releases/gnatprove_*/bin/gnatprove)
# The GNAT compiler is taken from $TOOL or the Alire gnat_native toolchain.
# The provers (Alt-Ergo / CVC5 / Z3) ship inside the gnatprove release and are
# found automatically.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

find_gnatprove() {
  if command -v gnatprove >/dev/null 2>&1; then
    command -v gnatprove
  elif [ -n "${GNATPROVE:-}" ] && [ -x "$GNATPROVE" ]; then
    printf '%s\n' "$GNATPROVE"
  else
    ls -1d "$HOME"/.local/share/alire/releases/gnatprove_*/bin/gnatprove 2>/dev/null | head -1
  fi
}

find_gnat_bin() {
  if [ -n "${TOOL:-}" ] && [ -x "$TOOL/gcc" ]; then
    printf '%s\n' "$TOOL"
  else
    ls -1d "$HOME"/.local/share/alire/toolchains/gnat_native_*/bin 2>/dev/null | head -1
  fi
}

GNATPROVE_BIN="$(find_gnatprove)"
if [ -z "$GNATPROVE_BIN" ] || [ ! -x "$GNATPROVE_BIN" ]; then
  echo "ERROR: gnatprove not found (PATH, \$GNATPROVE, or an Alire release)." >&2
  echo "Install it with 'alr install gnatprove' and retry." >&2
  exit 2
fi

GNAT_BIN="$(find_gnat_bin)"
if [ -z "$GNAT_BIN" ]; then
  echo "ERROR: GNAT compiler (gnat_native toolchain) not found." >&2
  exit 2
fi

export PATH="$(dirname "$GNATPROVE_BIN"):$GNAT_BIN:$PATH"

echo "GNATprove: $GNATPROVE_BIN"
echo "GNAT:      $GNAT_BIN/gcc"
echo "Proving verify.gpr (mode=all, level=4) ..."
gnatprove -P verify.gpr --mode=all --level=4
REPORT="obj/verify/gnatprove/gnatprove.out"
# Gate on the machine-readable report: a clean Level-4 run has no
# "not proved" entries.  (gnatprove exits 0 even when VCs are unproved —
# they are reported as "high" messages — so the report is the source of
# truth, not the exit code.)
if grep -q "not proved" "$REPORT"; then
  echo "ERROR: SPARK verification conditions remain UNPROVED (not-proved > 0)." >&2
  grep -n "not proved" "$REPORT" >&2 || true
  exit 1
fi
echo "SPARK proof passed: all verification conditions proved."

