#!/usr/bin/env bash
# Escalation check (AGENT_RULES v3.0 §2/§4): block commit if a Tier A file
# is staged without 'Approved-by: human' in the commit message.
# Usage (from .git/hooks/commit-msg): escalation_check.sh "$1"
set -euo pipefail

MSG_FILE="${1:-/dev/null}"

ALLOWLIST=(
  "schild_sel4_syscall.ads"   "schild_sel4_syscall.adb"
  "schild_root_task.adb"
  "schild_boot_manager.ads"   "schild_boot_manager.adb"
  "schild_audit_logger.ads"   "schild_audit_logger.adb"
  "schild_mls_policy.ads"     "schild_mls_policy.adb"
  "schild_cap_space.ads"      "schild_cap_space.adb"
  "schild_process_manager.ads" "schild_process_manager.adb"
  "schild_fs_server.ads"      "schild_fs_server.adb"
)

STAGED=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true)
[ -z "$STAGED" ] && exit 0

HITS=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  base=$(basename "$f")
  for a in "${ALLOWLIST[@]}"; do
    if [ "$base" = "$a" ]; then HITS="$HITS $f"; break; fi
  done
done <<< "$STAGED"

[ -z "$HITS" ] && exit 0

if [ -f "$MSG_FILE" ] && grep -qiE "^Approved-by:[[:space:]]*human" "$MSG_FILE"; then
  echo "ESCALATION OK: Tier A touched, Approved-by present:$HITS"
  exit 0
fi

echo "ESCALATION BLOCKED: Tier A files staged without approval:"
for f in $HITS; do echo "  $f"; done
echo ""
echo "Add 'Approved-by: human' as a line in the commit message, or revert."
exit 1
