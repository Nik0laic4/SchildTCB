#!/usr/bin/env bash
# =============================================================================
# Schild TCB -- CSpace slot-layout check (auditor suggestion #1).
#
# Verifies the static slot constants in schild_sel4_syscall.ads are unique
# (no two names reuse the same Slot_Base+N offset) and prints the daemon
# image/mint windows for a manual non-overlap review.  This catches the
# "Slot #N non-empty" class of collision at build time (before QEMU).
#
# Usage: ./check_slot_layout.sh
# =============================================================================
set -euo pipefail

ADS="$(cd "$(dirname "$0")/.." && pwd)/tools/sel4/src/schild_sel4_syscall.ads"
[ -f "$ADS" ] || { echo "ERROR: $ADS not found"; exit 1; }

# 1. Static uniqueness: every "Slot_Base + N" offset must be referenced once
#    (except Slot_Base itself, which is the base constant).
dups=$(grep -oE 'Slot_Base \+ [0-9]+' "$ADS" | awk '{print $3}' | sort | uniq -d)
if [ -n "$dups" ]; then
  echo "FAIL: duplicate slot offsets:"; echo "$dups" | sed 's/^/  +/'
  exit 1
fi
echo "PASS: no duplicate static slot offsets"

# 2. Daemon image/mint windows (image size is dynamic; review these against
#    the actual ELF sizes). Image_Base + size, mint = Image_Base + mint_offset.
echo
echo "Daemon windows (manual non-overlap review):"
grep -nE 'Image_Frame_Base|Mint_Offset|Shared_Frame_Slot|_PML4_Slot' "$ADS" \
  | grep -E ':= Slot_Base \+ [0-9]+' \
  | sed -E 's/^\s*//; s/\s*--.*$//' \
  | awk '{print "  " $0}'
