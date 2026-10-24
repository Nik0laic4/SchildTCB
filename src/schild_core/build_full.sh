#!/bin/bash
# DEPRECATED: legacy build entry point. The single canonical build is build.sh
# (fail-hard, two-circuit SCHILD_PROFILE). Kept only so old scripts keep
# working; it delegates to build.sh.
set -euo pipefail
cd "$(dirname "$0")"
exec ./build.sh "$@"
