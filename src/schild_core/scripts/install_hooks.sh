#!/usr/bin/env bash
# Install git hooks for AGENT_RULES v3.0. Run once after clone.
set -euo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

PRE_COMMIT='#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"
echo "[pre-commit] check_build_lists.sh..."
bash src/schild_core/scripts/check_build_lists.sh >/tmp/hook_build.log 2>&1 || { echo "[pre-commit] FAIL: build lists"; cat /tmp/hook_build.log; exit 1; }
echo "[pre-commit] forbidden_check.sh..."
bash src/schild_core/scripts/forbidden_check.sh || { echo "[pre-commit] FAIL: forbidden"; exit 1; }
echo "[pre-commit] OK"'

COMMIT_MSG='#!/usr/bin/env bash
set -euo pipefail
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"
bash src/schild_core/scripts/escalation_check.sh "$1" || { echo ""; echo "[commit-msg] Add Approved-by: human to commit message, or revert Tier A."; exit 1; }'

printf '%s\n' "$PRE_COMMIT" > .git/hooks/pre-commit
printf '%s\n' "$COMMIT_MSG" > .git/hooks/commit-msg
chmod +x .git/hooks/pre-commit .git/hooks/commit-msg
echo "Hooks installed: pre-commit, commit-msg"
