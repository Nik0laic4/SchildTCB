#!/usr/bin/env bash
# H68a: verify build_rt.sh compile vs link lists are consistent.
# Catches H67-class regressions (add module, forget one of two lists).
set -euo pipefail
RT="$(cd "$(dirname "$0")/.." && pwd)/tools/sel4/build_rt.sh"
[ -f "$RT" ] || { echo "ERROR: $RT not found"; exit 1; }

ADA_SRC=$(awk '/^for src in /,/; do$/' "$RT" \
  | sed '1s/^for src in //; $s/; do$//' | tr ' ' '\n' | grep -v '^$' || true)
ADA_SPEC=$(awk '/^for spec in /,/; do$/' "$RT" \
  | grep -vE '^for spec|; do' | sed 's/^ *//; s/ *\\$//; s/ *$//' \
  | grep -v '^$' | sed 's|.*/||' || true)
EXPLICIT=$(grep -oE '\-o "\$OBJ/[a-z_0-9]+\.o"' "$RT" \
  | sed -E 's/.*\$OBJ\/([a-z_0-9]+)\.o"/\1/' || true)
LINK=$(grep -oE '^\s+"\$OBJ/[a-z_0-9]+\.o"' "$RT" \
  | sed -E 's/^\s+"\$OBJ\/([a-z_0-9]+)\.o"/\1/' || true)

COMPILE=$(printf '%s\n%s\n%s\n' "$ADA_SRC" "$ADA_SPEC" "$EXPLICIT" | sort -u | grep -v '^$')
echo "compile: $(echo "$COMPILE" | wc -l), link: $(echo "$LINK" | wc -l)"

MISSING=""
for n in $COMPILE; do
  echo "$LINK" | grep -qx "$n" || MISSING="$MISSING $n"
done
if [ -n "$MISSING" ]; then
  echo "FAIL: compiled but not linked:$MISSING"
  echo "Fix: add \"\$OBJ/NAME.o\" to link list in build_rt.sh"
  exit 1
fi

EXTRA=""
for n in $LINK; do
  echo "$COMPILE" | grep -qx "$n" || EXTRA="$EXTRA $n"
done
[ -n "$EXTRA" ] && echo "WARN: link-only (spec-only Ada OK):$EXTRA"

echo "PASS: compile/link lists consistent"
