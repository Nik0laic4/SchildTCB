#!/usr/bin/env bash
# Forbidden checks (AGENT_RULES v3.0 section 3).
# Match real code, not comments (Ada -- / shell #).
set -euo pipefail

STAGED=$(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true)
[ -z "$STAGED" ] && exit 0

DIFF=$(git diff --cached --no-color -U0 2>/dev/null || true)
[ -z "$DIFF" ] && exit 0

FAIL=0

# 1. pragma Assume (code lines only, not comments)
H1=$(echo "$DIFF" | grep -E '^\+[[:space:]]*pragma[[:space:]]+Assume' || true)
if [ -n "$H1" ]; then
  echo "FORBIDDEN: pragma Assume added"
  echo "$H1" | head -3
  FAIL=1
fi

# 2. Post => True (code lines only)
H2=$(echo "$DIFF" | grep -E '^\+[[:space:]]*Post[[:space:]]*=>[[:space:]]*\(?True\)?' || true)
if [ -n "$H2" ]; then
  echo "FORBIDDEN: Post => True (vacuous contract)"
  echo "$H2" | head -3
  FAIL=1
fi

# 3. SPARK_Mode => Off in Tier A file (added lines)
ALLOWLIST_RE='schild_sel4_syscall\.(ads|adb)|schild_root_task\.adb|schild_boot_manager\.(ads|adb)|schild_audit_logger\.(ads|adb)|schild_mls_policy\.(ads|adb)|schild_cap_space\.(ads|adb)|schild_process_manager\.(ads|adb)|schild_fs_server\.(ads|adb)'
NEW_TIER_A=$(echo "$STAGED" | grep -E "$ALLOWLIST_RE" || true)
for f in $NEW_TIER_A; do
  H3=$(git diff --cached -- "$f" 2>/dev/null | grep -E '^\+[[:space:]]*SPARK_Mode[[:space:]]*=>[[:space:]]*Off' || true)
  if [ -n "$H3" ]; then
    echo "FORBIDDEN: SPARK_Mode => Off in Tier A: $f"
    FAIL=1
  fi
done

# 4. Gate disabled: "|| true" attached to a gate command, or "set +e"
GATE_KW='(build\.sh|verify\.sh|verify_private\.sh|run_tests\.sh|prove_kernel\.sh|check_build_lists\.sh|build_rt\.sh)'
H4=$(echo "$DIFF" | grep -E "^\+[[:space:]]*[^#].*${GATE_KW}.*\|\|[[:space:]]*true" || true)
H4B=$(echo "$DIFF" | grep -E '^\+[[:space:]]*set[[:space:]]+\+e' || true)
if [ -n "$H4" ] || [ -n "$H4B" ]; then
  echo "FORBIDDEN: gate disabled (gate cmd || true, or set +e)"
  [ -n "$H4" ] && echo "$H4" | head -3
  [ -n "$H4B" ] && echo "$H4B" | head -3
  FAIL=1
fi

# 5. Test deletion (WARN only)
REMOVED=$(echo "$DIFF" | grep -cE '^\-.*(pragma[[:space:]]+Assert|assert\(|TEST\()' || true)
[ "$REMOVED" -gt 0 ] && echo "WARN: $REMOVED test/assert lines removed"

[ "$FAIL" -eq 0 ] && echo "FORBIDDEN CHECK: PASS"
exit "$FAIL"
