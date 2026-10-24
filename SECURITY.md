# Security Policy

## Supported versions

| Version | Supported |
|---------|-----------|
| `master` (x86_64) | ✅ |
| `arm64` (Raspberry Pi 4B) | ✅ (pre-release) |

## Reporting a vulnerability

Please do **not** open a public issue for security vulnerabilities.

Report privately to the maintainer (see the Git commit author / GitHub profile).

## Security model

Schild TCB is a research prototype. Its security claims are stated **per-component**:

- **Proven core** (MLS policy, capability model) — formally verified with SPARK (Level 4, `not-proved: 0`).
- **Isolated periphery** (e1000e, NVMe, network stack) — contained in Ring-3 domains; a compromise cannot reach the proven core.
- **Known gaps** — IOMMU/VT-d DMA isolation is pending (upstream); x86_64 MCS is formally verified weaker than ARM MCS (upstream).

See [`docs/technical/ASSURANCE.md`](docs/technical/ASSURANCE.md) for the full assurance case.
