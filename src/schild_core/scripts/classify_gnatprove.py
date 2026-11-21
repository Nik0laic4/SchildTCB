#!/usr/bin/env python3
"""Deterministic per-module classifier for a gnatprove.out file.

Usage:
    classify_gnatprove.py OUT_FILE ROOT_DIR MODULE [MODULE ...]

Reads OUT_FILE (gnatprove's machine-readable output) once, splits it into
per-unit blocks by the "in unit <name>," markers, and prints one line per
requested module:

    <VERDICT padded to 12 chars> <module>

Verdicts (deterministic, independent of -j8 wording):

  - NOT-PROVED: the block contains "not proved".
  - PROVED:     the block contains "proved (" (any number of checks).
  - SKIPPED:    the module body is SPARK_Mode => Off — out of proof scope by
                design. Determined by reading the BODY TEXT, not by the
                gnatprove verdict, so it no longer conflates "body Off" with
                "unit missing from the -j8 output" (F2).
  - NO-OUTPUT:  the body is On but gnatprove emitted no verdict block. A
                distinct signal (previously lumped into SKIPPED) that should
                be investigated — an On unit with no output is not "out of
                scope".
"""
import os
import re
import sys

# F7: child packages (Schild_X.Child) carry a dot in the unit name.
IN_UNIT_RE = re.compile(r"^in unit ([A-Za-z0-9_.]+),")

# A body is out of proof scope (SKIPPED) iff it declares SPARK_Mode => Off or
# pragma SPARK_Mode (Off). Case-insensitive to cover "Spark_Mode (Off)".
OFF_MODE_RE = re.compile(
    r"SPARK_Mode\s*(?:=>|:)\s*Off|SPARK_Mode\s*\(\s*Off\s*\)", re.IGNORECASE)


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


def find_body(root_dir, module):
    """Return the path to module.adb under root_dir/src, or None."""
    for dirpath, _, files in os.walk(os.path.join(root_dir, "src")):
        name = module + ".adb"
        if name in files:
            return os.path.join(dirpath, name)
    return None


def body_is_off(root_dir, module):
    path = find_body(root_dir, module)
    if path is None:
        return False
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            return bool(OFF_MODE_RE.search(f.read()))
    except OSError:
        return False


def verdict(block_lines, root_dir, module):
    if body_is_off(root_dir, module):
        return "SKIPPED"
    blob = "".join(block_lines)
    if "not proved" in blob:
        return "NOT-PROVED"
    if "proved (" in blob:
        return "PROVED"
    return "NO-OUTPUT"


def main():
    if len(sys.argv) < 4:
        sys.exit(__doc__)
    out_path = sys.argv[1]
    root_dir = sys.argv[2]
    modules = sys.argv[3:]
    blocks = blocks_from(out_path)
    for m in modules:
        print(f"{verdict(blocks.get(m, []), root_dir, m):<12} {m}")


if __name__ == "__main__":
    main()
