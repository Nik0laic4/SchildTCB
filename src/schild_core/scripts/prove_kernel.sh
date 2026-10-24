#!/usr/bin/env bash
# Schild TCB standalone-kernel SPARK Level-4 proof, batched.
#
# Proving modules in chunks is equivalent to a single end-to-end run: SPARK
# proves each unit against its own spec, so the per-module verdict is identical.
# This script chunks the ~180 kernel modules (BATCH per gnatprove invocation)
# and writes a per-module verdict report + aggregate.
#
# Usage:
#   bash scripts/prove_kernel.sh              # all modules
#   BATCH=20 bash scripts/prove_kernel.sh     # 20 modules per chunk (default)
set -u

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

GP="$(ls -1d "$HOME"/.local/share/alire/releases/gnatprove_*/bin/gnatprove 2>/dev/null | head -1)"
GNAT="$(ls -1d "$HOME"/.local/share/alire/toolchains/gnat_native_*/bin 2>/dev/null | head -1)"

if [ -z "$GP" ] || [ ! -x "$GP" ]; then
  echo "ERROR: gnatprove not found (~/.local/share/alire/releases/gnatprove_*/bin)." >&2
  echo "Install it with 'alr install gnatprove' and retry." >&2
  exit 2
fi
if [ -z "$GNAT" ] || [ ! -x "$GNAT/gcc" ]; then
  echo "ERROR: GNAT compiler (gnat_native toolchain) not found." >&2
  exit 2
fi

export PATH="$(dirname "$GP"):$GNAT:$PATH"

BATCH="${BATCH:-20}"
OUT="${OUT:-obj/proof/report.txt}"
mkdir -p obj/proof
: > "$OUT"

# Exclude the null-stub directory (src/04_userland/null/): its ledger stub is a
# build artifact compiled only in the public profile, not a proof source, and it
# is not listed in the proof project's Source_Dirs (gnatprove would fail on it).
mapfile -t MODS < <(find src -name '*.adb' -not -path '*/null/*' -exec basename {} .adb \; | sort)
TOTAL=${#MODS[@]}
echo "modules: $TOTAL" >&2

for ((i=0; i<TOTAL; i+=BATCH)); do
  chunk=("${MODS[@]:i:BATCH}")
  mains=""
  for m in "${chunk[@]}"; do mains+=" \"$m.adb\","; done
  mains="${mains%,}"
  cat > /tmp/proof_batch.gpr <<EOF
project Proof_Batch is
   for Source_Dirs use ("$ROOT_DIR/src",
                        "$ROOT_DIR/src/01_hardware",
                        "$ROOT_DIR/src/02_security",
                        "$ROOT_DIR/src/03_crypto",
                        "$ROOT_DIR/src/04_userland");
   for Object_Dir use "$ROOT_DIR/obj/proof";
   for Main use ($mains);
   package Compiler is
      for Default_Switches ("Ada") use ("-gnat2022", "-gnatwa");
   end Compiler;
end Proof_Batch;
EOF
  rm -rf obj/proof/gnatprove
  gnatprove -P /tmp/proof_batch.gpr --level=4 --mode=all -j8 > /tmp/proof_batch.log 2>&1
  outfile=obj/proof/gnatprove/gnatprove.out
  for m in "${chunk[@]}"; do
    v=$(awk -v u="$m" '
      $0 ~ ("^in unit " u ",") { inblock=1; next }
      inblock && /^in unit / { exit }
      inblock && /not proved/ { np=1 }
      inblock && /skipped/ { s=1 }
      inblock && /proved \(/ { p=1 }
      END {
        if (np) print "NOT-PROVED";
        else if (!p && s) print "SKIPPED";
        else if (p) print "PROVED";
        else print "NO-BODY";
      }' "$outfile")
    printf '%-12s %s\n' "$v" "$m" >> "$OUT"
  done
  echo "chunk $((i/BATCH+1))/$(( (TOTAL+BATCH-1)/BATCH )) done" >&2
done

echo "=== SUMMARY ===" >> "$OUT"
echo "total      : $TOTAL" >> "$OUT"
echo "proved     : $(grep -c '^PROVED' "$OUT" || true)" >> "$OUT"
echo "not-proved : $(grep -c '^NOT-PROVED' "$OUT" || true)" >> "$OUT"
echo "skipped    : $(grep -c '^SKIPPED' "$OUT" || true)" >> "$OUT"
echo "no-body    : $(grep -c '^NO-BODY' "$OUT" || true)" >> "$OUT"

# Gate: fail hard if any module is NOT-PROVED (Level-4 claim is "not-proved: 0").
NOTPROVED=$(grep -c '^NOT-PROVED' "$OUT" || true)
if [ "$NOTPROVED" -ne 0 ]; then
  echo "ERROR: $NOTPROVED module(s) NOT-PROVED (see $OUT)." >&2
  grep '^NOT-PROVED' "$OUT" >&2 || true
  exit 1
fi

echo "Report: $OUT"
