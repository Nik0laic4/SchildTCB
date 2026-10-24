#!/usr/bin/env bash
# Schild TCB test entry point (legacy name kept for compatibility).
# Delegates to the canonical QEMU smoke-test harness.
set -euo pipefail
exec "$(dirname "$0")/scripts/run_tests.sh" "$@"
