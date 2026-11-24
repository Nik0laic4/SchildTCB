#!/usr/bin/env bash
# Tier-A dependency audit (review #11): list the `with` dependencies of each
# Tier-A unit and flag any whose BODY is SPARK_Mode => Off (i.e. the Tier-A
# unit depends on an unproved body, not merely a specification). The tier rule
# is "Tier A depends on Tier-B specifications, never Tier-B bodies".
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT_DIR/src"

ALLOWLIST='schild_sel4_syscall|schild_root_task|schild_boot_manager|schild_audit_logger|schild_mls_policy|schild_cap_space|schild_process_manager|schild_fs_server'

files=$(find "$SRC" \( -name '*.ads' -o -name '*.adb' \) \
        | grep -E "/($ALLOWLIST)\.(ads|adb)$" | sort || true)

viol=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  base="$(basename "$f")"
  deps=$(grep -oE '^[[:space:]]*with[[:space:]]+[A-Za-z0-9_.]+' "$f" \
         | sed -E 's/.*with[[:space:]]+//' | sort -u || true)
  off=""
  for d in $deps; do
    case "$d" in System|Interfaces|Ada.*) continue;; esac
    fname=$(echo "$d" | tr '.' '-' | tr '[:upper:]' '[:lower:]')
    body=$(find "$SRC" -name "${fname}.adb" 2>/dev/null | head -1 || true)
    if [ -n "$body" ] && [ "$(grep -cE 'SPARK_Mode[[:space:]]*=>[[:space:]]*Off' "$body" 2>/dev/null || true)" -gt 0 ]; then
      off="$off ${d}"
    fi
  done
  if [ -n "$off" ]; then
    echo "TIER-DEP VIOLATION: $base -> Off bodies:$off"
    viol=$((viol + 1))
  fi
done <<< "$files"
echo "check_tier_deps: $viol violations"
