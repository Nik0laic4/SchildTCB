#!/usr/bin/env bash
# Schild TCB — metrics consistency gate (Приоритет 2).
#
# Verifies the canonical proof metrics (obj/proof/metrics.json, written by
# prove_kernel.sh) are internally consistent AND that README.md states the same
# numbers. This is the "README numbers never drift from the machine-generated
# metrics" check (auditor §4.3). Requires a prior prove_kernel.sh run; when the
# metrics file is absent the check exits 0 (prove-full is the only job that
# generates it).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

METRICS="obj/proof/metrics.json"
if [ ! -f "$METRICS" ]; then
  echo "metrics.json not found (run prove_kernel.sh first) — skipping."
  exit 0
fi

num() { grep -o "\"$1\": [0-9]*" "$METRICS" | grep -o '[0-9]*$'; }

SWEPT="$(num swept)"
IN_PROOF="$(num in_proof)"
PROVED="$(num proved)"
SKIPPED="$(num skipped)"
NOTPROVED="$(num not_proved)"
NOOUTPUT="$(num no_output)"
SCAFFOLD="$(num scaffold_excluded)"

if [ "$((PROVED + NOTPROVED + SKIPPED + NOOUTPUT))" -ne "$IN_PROOF" ]; then
  echo "ERROR: proved($PROVED)+not_proved($NOTPROVED)+skipped($SKIPPED)+no_output($NOOUTPUT) != in_proof($IN_PROOF)" >&2
  exit 1
fi
if [ "$((IN_PROOF + SCAFFOLD))" -ne "$SWEPT" ]; then
  echo "ERROR: in_proof($IN_PROOF)+scaffold($SCAFFOLD) != swept($SWEPT)" >&2
  exit 1
fi

# README must state the canonical "swept / in proof" figures.
README="$ROOT_DIR/../../README.md"
if ! grep -q "$SWEPT kernel modules swept" "$README"; then
  echo "ERROR: README.md does not state \"$SWEPT kernel modules swept\"." >&2
  exit 1
fi
if ! grep -q "$IN_PROOF in proof\|$IN_PROOF proved\|$IN_PROOF-module" "$README"; then
  echo "ERROR: README.md does not state the in-proof count $IN_PROOF." >&2
  exit 1
fi

echo "metrics consistency OK: swept=$SWEPT in_proof=$IN_PROOF proved=$PROVED not_proved=$NOTPROVED skipped=$SKIPPED no_output=$NOOUTPUT scaffold=$SCAFFOLD"
