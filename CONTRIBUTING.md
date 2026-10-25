# Contributing

Schild TCB is a single-author research prototype, but contributions and feedback are welcome.

## Reporting issues

Open an issue describing the problem, the expected behavior, and (if possible) steps to reproduce.

## Development

- Language: Ada/SPARK 2022 (with C and ASM), seL4 microkernel.
- Formal verification: SPARK Level 4, 0 unproved VCs (108 of 185 kernel modules proved) — keep the proof gate green.
- Two branches: `master` (x86_64) and `arm64` (Raspberry Pi 4B).

## Style

- Neutral, dry technical language (no marketing).
- SPDX headers on all files (`GPL-2.0-only`).
- Verified results only in the changelog.

## License

By contributing, you agree that your contributions are licensed under GPL-2.0-only.
