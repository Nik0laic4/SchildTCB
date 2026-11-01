#!/usr/bin/env bash
# Schild TCB — private-profile SPARK proof gate.
#
# Proves the FULL (private) daemon bodies from private/root_task/ against the
# public stub specs in tools/sel4/src — the same overlay that build_rt.sh
# applies for SCHILD_PROFILE=private. This closes the former "private build is
# compiled but not formally proved" boundary.
#
#   schild_audit_logger.adb   SPARK_Mode => On (Persist_Audit_Log is Off — I/O)
#   schild_config_daemon.adb  SPARK_Mode => On
#   schild_boot_manager.adb   SPARK_Mode => On
#
# Gate: fails on any "not proved" verification condition (same policy as
# verify.sh). Run:  bash scripts/verify_private.sh
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
  exit 2
fi

GNAT_BIN="$(find_gnat_bin)"
if [ -z "$GNAT_BIN" ]; then
  echo "ERROR: GNAT compiler (gnat_native toolchain) not found." >&2
  exit 2
fi

export PATH="$(dirname "$GNATPROVE_BIN"):$GNAT_BIN:$PATH"

# Stage the stub specs/bodies + private .adb overlay (mirrors build_rt.sh's
# overlay; gnatprove needs one Source_Dir without duplicate unit names).
STAGE="$ROOT_DIR/obj/verify_private/stage"
rm -rf "$ROOT_DIR/obj/verify_private"
mkdir -p "$STAGE" "$ROOT_DIR/obj/verify_private/obj"
cp "$ROOT_DIR"/tools/sel4/src/*.ads "$STAGE/"
cp "$ROOT_DIR"/tools/sel4/src/*.adb "$STAGE/"
cp "$ROOT_DIR"/../../private/root_task/schild_audit_logger.adb  "$STAGE/"
cp "$ROOT_DIR"/../../private/root_task/schild_config_daemon.adb "$STAGE/"
cp "$ROOT_DIR"/../../private/root_task/schild_boot_manager.adb  "$STAGE/"

cat > /tmp/verify_private.gpr <<GPR
project Verify_Private is
   for Source_Dirs use ("$STAGE",
                        "$ROOT_DIR/src/03_crypto",
                        "$ROOT_DIR/src/04_userland",
                        "$ROOT_DIR/src/01_hardware",
                        "$ROOT_DIR/src/02_security",
                        "$ROOT_DIR/src");
   for Object_Dir use "$ROOT_DIR/obj/verify_private/obj";
   for Main use ("schild_audit_logger.adb",
                 "schild_config_daemon.adb",
                 "schild_boot_manager.adb");
   package Compiler is
      for Default_Switches ("Ada") use ("-gnat2022", "-gnatwa");
   end Compiler;
end Verify_Private;
GPR

echo "GNATprove: $GNATPROVE_BIN"
echo "Proving private daemon bodies (level=4, mode=all) ..."
gnatprove -P /tmp/verify_private.gpr --level=4 --mode=all

REPORT="$ROOT_DIR/obj/verify_private/obj/gnatprove/gnatprove.out"
if grep -q "not proved" "$REPORT"; then
  echo "ERROR: private daemons have unproved verification conditions." >&2
  grep -n "not proved" "$REPORT" >&2 || true
  exit 1
fi
echo "Private profile proof passed: all verification conditions proved."
