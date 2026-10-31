#!/usr/bin/env python3
"""Deterministic per-module classifier for a gnatprove.out file.

Usage:
    classify_gnatprove.py OUT_FILE MODULE [MODULE ...]

Reads OUT_FILE (gnatprove's machine-readable output) once, splits it into
per-unit blocks by the "in unit <name>," markers, and prints one line per
requested module in the report format:

    <VERDICT padded to 12 chars> <module>

Verdicts (same semantics as the historical report):

  - NOT-PROVED: the block contains "not proved".
  - PROVED:     otherwise, the block contains "proved (" (any number of checks).
  - SKIPPED:    otherwise, the block contains "skipped" (body SPARK_Mode => Off).
  - NO-BODY:    none of the above (absent or empty block).

The awk version this replaces scanned the file once per module and was fragile
around block boundaries, which made the SKIPPED/NO-BODY split drift between
runs. Parsing the file once into a dict is deterministic.
"""
import re
import sys

IN_UNIT_RE = re.compile(r"^in unit ([A-Za-z0-9_]+),")


def blocks_from(path):
    """Return {unit_name: [lines after its 'in unit' marker]}."""
    blocks = {}
    current = None
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = IN_UNIT_RE.match(line)
            if m:
                current = m.group(1)
                blocks[current] = []
            elif current is not None:
                blocks[current].append(line)
    return blocks


def verdict(block_lines):
    blob = "".join(block_lines)
    if "not proved" in blob:
        return "NOT-PROVED"
    if "proved (" in blob:
        return "PROVED"
    if "skipped" in blob:
        return "SKIPPED"
    return "NO-BODY"


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    out_path = sys.argv[1]
    modules = sys.argv[2:]
    blocks = blocks_from(out_path)
    for m in modules:
        print(f"{verdict(blocks.get(m, [])):<12} {m}")


if __name__ == "__main__":
    main()
