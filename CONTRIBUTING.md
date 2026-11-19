# Contributing to Schild TCB

Thank you for your interest in Schild TCB. This is a single-author research prototype, but feedback, bug reports, and contributions are very welcome.

## How to help right now

The project is actively evolving, and here are the areas where help is most needed:

- **Hardware testing (ARM64):** I need someone with a physical Raspberry Pi 4B to test the `arm64` branch and help write the GENET Ethernet driver. QEMU does not emulate GENET, so I am blocked without real hardware.
- **SPARK contract review:** If you are familiar with Ada/SPARK, please look at the contracts in the core modules. If you see a contract that looks too weak or a proof that was "forced" through a workaround, open an issue.
- **Code review:** The seL4 syscall seam (`schild_sel4_syscall.adb`) and the MCS scheduling logic are complex. A fresh pair of eyes is always helpful.
- **Documentation:** If something in the `docs/` folder is confusing or missing, let me know.

## Reporting issues

Open an issue describing the problem, the expected behavior, and (if possible) steps to reproduce. If you are reporting a bug in the proof (e.g., a VC that fails on your machine but passes on mine), please include the `gnatprove` version and the output.

## Development

- Language: Ada/SPARK 2022 (with C and ASM), seL4 microkernel.
- Formal verification: SPARK Level 4, 0 unproved VCs (188 modules swept: 132 proved / 48 outside / 8 scaffold excluded). Keep the proof gate green.
- Branches: `master` (x86_64) and `arm64` (Raspberry Pi 4B) — currently in sync at the same commit (the tree carries both targets).

## Language policy

Three tiers, by audience:

- **Level 1 — "storefront" (bilingual):** `README`, `ASSURANCE`, `THREAT_MODEL`, `SECURITY` must exist in both English (`.md`) and Russian (`.ru.md`). A number changed in one must change in the other — `scripts/check_metrics_consistency.sh` keeps the key counts honest.
- **Level 2 — methodology (RU first):** `docs/methodology/` is written in Russian (the author's native language and the source for Habr posts); English translation is produced on demand (per article / arXiv).
- **Level 3 — technical logs (EN only):** `CHANGELOG`, `ROADMAP`, `BUILD`, `AUDIT_REGISTRY` (internal) stay in English for consistency with commits. Historical documents are not retro-translated.

## Style

- Neutral, dry technical language (no marketing).
- SPDX headers on all files (`GPL-2.0-only`).
- Verified results only in the changelog.

## License

By contributing, you agree that your contributions are licensed under GPL-2.0-only.

The project may offer a separate commercial license for use in closed-source products (dual licensing). By contributing, you agree that your contributions may be distributed under both the GPL-2.0-only and such a commercial license.
