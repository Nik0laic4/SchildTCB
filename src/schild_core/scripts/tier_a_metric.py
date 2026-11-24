#!/usr/bin/env python3
"""Tier-A coverage metric (review #7): count SPARK_Mode => On subprograms in
the Tier-A units, so the 'N in proof' denominator no longer conflates On and
Off bodies. Source-level (procedure/function declarations), not gnatprove XML:
the gnatprove invocation emits text only, so this is a cheap approximation of
the requested 'X subprograms On / Y total'."""
import os, re, sys

ALLOWLIST = ['schild_sel4_syscall', 'schild_root_task', 'schild_boot_manager',
             'schild_audit_logger', 'schild_mls_policy', 'schild_cap_space',
             'schild_process_manager', 'schild_fs_server']

SUB_RE = re.compile(r'^\s*(procedure|function)\s+[A-Za-z0-9_]+', re.M)
OFF_RE = re.compile(r'SPARK_Mode\s*(?:=>|:)\s*Off|SPARK_Mode\s*\(\s*Off\s*\)', re.I)

def find_files(root):
    for dirpath, _, files in os.walk(root):
        for f in files:
            if f.endswith(('.ads', '.adb')):
                base = f[:-4]
                if any(base == a or base.startswith(a + '-') for a in ALLOWLIST):
                    yield os.path.join(dirpath, f)

def main():
    roots = sys.argv[1:] or ['src/schild_core/src', 'src/schild_core/tools/sel4/src']
    on_subs = off_subs = on_units = off_units = 0
    for root in roots:
        for f in find_files(root):
            txt = open(f, encoding='utf-8', errors='replace').read()
            n = len(SUB_RE.findall(txt))
            if OFF_RE.search(txt):
                off_units += 1; off_subs += n
            else:
                on_units += 1; on_subs += n
    total = on_subs + off_subs
    print(f"Tier A: {on_subs} subprograms On / {total} total "
          f"({on_units} On units + {off_units} Off units)")
    return 0

if __name__ == '__main__':
    sys.exit(main())
