#!/usr/bin/env bash
# =============================================================================
# sanitize_paths.sh — post-build path sanitizer for Schild TCB.
#
# GNAT records the host's absolute source and run-time paths inside generated
# compiler artifacts: `.ali` dependency records, GNATprove `.cswi` switch
# files, and per-unit `.log` files. Those absolute paths embed the host
# username and the host directory layout, which can otherwise leak into
# verification material (e.g. the SPARK Log-Check package).
#
# This script rewrites every such absolute host path to a neutral, portable
# placeholder so that no host or non-ASCII directory metadata survives in the
# build outputs.
#
# The compiler-side hardening (build.sh / build_rt.sh / schild_core.gpr) maps
# the build root to a relative prefix via -fdebug-prefix-map and
# -fmacro-prefix-map; this script covers the remaining text artifacts that
# those switches do not touch (.ali / .cswi / .log / .stdout).
#
# Usage:
#   bash scripts/sanitize_paths.sh [target-root]
#
#   target-root  defaults to the repository root. The neutral placeholders are
#   configurable via SCHILD_SANITIZED_ROOT (default /home/build/SchildTCB)
#   and SCHILD_SANITIZED_HOME (default /home/build).
# =============================================================================
set -euo pipefail

NEUTRAL_ROOT="${SCHILD_SANITIZED_ROOT:-/home/build/SchildTCB}"
NEUTRAL_HOME="${SCHILD_SANITIZED_HOME:-/home/build}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
TARGET_ROOT="${1:-${REPO_ROOT}}"

# Absolute (symlink-resolved) build root exactly as the compiler recorded it.
BUILD_ROOT="$(cd "${TARGET_ROOT}" 2>/dev/null && pwd || printf '%s' "${TARGET_ROOT}")"
HOME_DIR="${HOME}"

echo "[sanitize_paths] build root   : ${BUILD_ROOT}"
echo "[sanitize_paths] neutral root : ${NEUTRAL_ROOT}"
echo "[sanitize_paths] home         : ${HOME_DIR} -> ${NEUTRAL_HOME}"

# Escape a value for use as a sed BRE search pattern (delimiter '|').
sed_escape_pattern() {
  printf '%s' "$1" | sed -e 's/[].[*^$\\|]/\\&/g'
}
# Escape a value for use as a sed replacement.
sed_escape_replacement() {
  printf '%s' "$1" | sed -e 's/[&\\|]/\\&/g'
}

OLD_ROOT_PAT="$(sed_escape_pattern "${BUILD_ROOT}")"
OLD_HOME_PAT="$(sed_escape_pattern "${HOME_DIR}")"
NEW_ROOT="$(sed_escape_replacement "${NEUTRAL_ROOT}")"
NEW_HOME="$(sed_escape_replacement "${NEUTRAL_HOME}")"

# Generated artifact directories and extensions known to embed compiler paths.
# Loose text-artifact extensions anywhere (defensive coverage outside obj/).
ARTIFACT_EXT='-name *.ali -o -name *.cswi -o -name *.log -o -name *.stdout
              -o -name *.stderr -o -name *.spark -o -name *.out -o -name *.bak
              -o -name *.xml -o -name *.json -o -name *.gnat-json -o -name *.txt
              -o -name *.trace -o -name *.conf'

collect_files() {
  # 1) Every file under an obj/ build-cache directory (GNAT / SPARK artifacts),
  #    including extensionless files (binder output, KAT test artifacts).
  while IFS= read -r -d '' d; do
    find "${d}" -type f -print0 2>/dev/null
  done < <(find "${TARGET_ROOT}" -type d -name .git -prune -o -type d -name obj -print0 2>/dev/null || true)
  # 2) Loose text artifacts elsewhere in the tree.
  # shellcheck disable=SC2086
  find "${TARGET_ROOT}" -type d -name .git -prune -o -type f \( ${ARTIFACT_EXT} \) -print0 2>/dev/null || true
}

mapfile -d '' FILES < <(collect_files)

CHANGED=0
for f in "${FILES[@]}"; do
  [ -f "${f}" ] || continue
  # `grep -I` treats binary files (.o / ELF / why3shapes) as non-matching, so a
  # length-changing substitution never corrupts them; binary DWARF paths are
  # handled at compile time by -fdebug-prefix-map / -fmacro-prefix-map.
  if grep -aqI -- "${BUILD_ROOT}" "${f}" 2>/dev/null || grep -aqI -- "${HOME_DIR}" "${f}" 2>/dev/null; then
    sed -i \
      -e "s|${OLD_ROOT_PAT}|${NEW_ROOT}|g" \
      -e "s|${OLD_HOME_PAT}|${NEW_HOME}|g" \
      "${f}"
    CHANGED=$((CHANGED + 1))
  fi
done

echo "[sanitize_paths] files scanned : ${#FILES[@]}"
echo "[sanitize_paths] files changed : ${CHANGED}"

# Verification sweep: no host root / home path may remain in any text artifact.
REMAINING_TEXT=0
REMAINING_BINARY=0
while IFS= read -r -d '' f; do
  if grep -aqI -- "${BUILD_ROOT}" "${f}" 2>/dev/null || grep -aqI -- "${HOME_DIR}" "${f}" 2>/dev/null; then
    echo "[sanitize_paths] WARNING: residual host path in ${f}" >&2
    REMAINING_TEXT=$((REMAINING_TEXT + 1))
  elif grep -aqF -- "${BUILD_ROOT}" "${f}" 2>/dev/null || grep -aqF -- "${HOME_DIR}" "${f}" 2>/dev/null; then
    # Binary artifact still carries the path in DWARF: rebuilt cleanly by the
    # compile-time prefix-map switches (informational, not a sanitizer failure).
    REMAINING_BINARY=$((REMAINING_BINARY + 1))
  fi
done < <(collect_files)

echo "[sanitize_paths] residual text artifacts   : ${REMAINING_TEXT}"
echo "[sanitize_paths] binary artifacts (prefix-map) : ${REMAINING_BINARY}"

if [ "${REMAINING_TEXT}" -eq 0 ]; then
  echo "[sanitize_paths] verification : 0 residual host-path occurrences in text artifacts"
else
  echo "[sanitize_paths] verification : ${REMAINING_TEXT} text artifact(s) still contain host paths" >&2
  exit 1
fi

