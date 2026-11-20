# Schild TCB

A **Trusted Computing Base (TCB)** research prototype: a formally verified core (**seL4** microkernel + **Ada/SPARK 2022**) with an isolated-peripheral environment.

[![OpenSSF Best Practices](https://www.bestpractices.dev/projects/16898/badge)](https://www.bestpractices.dev/projects/16898)
[![CI (build+verify)](https://github.com/Nik0laic4/SchildTCB/actions/workflows/ci.yml/badge.svg)](https://github.com/Nik0laic4/SchildTCB/actions/workflows/ci.yml)
[![ARM64 virtio-net](https://github.com/Nik0laic4/SchildTCB/actions/workflows/arm64-net.yml/badge.svg)](https://github.com/Nik0laic4/SchildTCB/actions/workflows/arm64-net.yml)
[![SPARK Level 4](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/Nik0laic4/7221682b51fce1403d41fa9584f3d102/raw/spark-badge.json)](docs/technical/ASSURANCE.md)
[![License: GPL-2.0-only](https://img.shields.io/badge/License-GPL--2.0--only-blue.svg)](LICENSE)

---

## What is this

Schild TCB is a research prototype of a microkernel-based trusted computing base. It is two artifacts, not one:

1. **A bare-metal OS** written from scratch in Ada — bootloader, NVMe driver, e1000e NIC driver, TCP/IP stack, HTTP server. Runs on a ThinkPad T580 and in QEMU. Answers *"does it work"*.
2. **An seL4-based artifact** — the microkernel is upstream seL4 (formally verified; locally patched for x86_64 MCS and hardware support, see [`SEL4_PATCHES_ANALYSIS.md`](docs/technical/SEL4_PATCHES_ANALYSIS.md)), and the contribution is an Ada/SPARK **root task** plus several daemons. Network and storage run **isolated in Ring 3** processes, communicating over IPC. Answers *"is it proven"*.

**This is not a product, not a Linux replacement, and not a certified system.** It is an open reference architecture and methodology for building trusted computing bases on seL4. The value is in the approach, the assurance case, and the documented engineering decisions, not in shipping a ready-to-use OS.

## Method & Roles

This repository is produced by a documented **human–machine pipeline**, not a lone developer:

- **Author (human)** — architecture, requirements, audit registry, and control; holds the Tier-A boundary and every assurance claim.
- **AI agent** — generates code, edits contracts, hunts for defects; nothing ships past the gates and the human review.
- **SPARK/gnatprove** — the impartial oracle; `not-proved: 0` is a machine-checked fact, not an assertion.

The pipeline rules ("AI-agent constitution"), the escalation model, and the worked case studies (e.g. the H61 misaligned-stack bug the prover could not catch) live in [`docs/methodology/`](docs/methodology/).

## Highlights

- **Formal verification** — **188 kernel modules swept** at **SPARK Level 4** (`gnatprove --level=4 --mode=all`) — **180 in proof set: 132 proved, 48 skipped; 8 scaffold excluded** — with **0 unproved VCs** (see [`ASSURANCE.md`](docs/technical/ASSURANCE.md) §2.2). 8 root-task proof units (root task + 7 libraries/models — MLS policy, capability/process/firewall models, boot manager, HM/launch models, watchdog) are also proved. *(A few modules — `schild_firewall`, `schild_signals`, `schild_frame_allocator`, `schild_server_security_policy` — are provable at Level 4 in a focused run but may be classified `SKIPPED` by the canonical `-j8` batch; the stable gate is `not-proved: 0`. See [`SPARK_PROOF_TECHNIQUES.md`](docs/technical/SPARK_PROOF_TECHNIQUES.md).)*
- **Isolated periphery** — network (e1000e → I219-V) and storage (NVMe + SchildFS) run in the isolated Ring-3 **NetServer**; a fault there cannot reach the proven core.
- **MLS Bell-LaPadula** — 5 security levels in the seL4 layer (Public..Top_Secret), 4 in the bare-metal kernel.
- **Crash containment** — faulting a driver is caught and contained without rebooting the platform.
- **Boots on real hardware** — ThinkPad T580 (32 GB) and QEMU.

## Architecture

| Layer | Purpose |
|-------|---------|
| `01_hardware` | MMU, APIC/IOAPIC, NVMe, e1000e, SMP, PIT timer |
| `02_security` | MLS Bell-LaPadula, capability model, IPC gateway, firewall |
| `03_crypto` | AES-NI, SHA-256, HMAC-SHA256 (FIPS 198-1), RNG |
| `04_userland` | SchildFS/VFS, sockets, network stack (ARP/IPv4/TCP/UDP/HTTP) |

## Verification status (honest boundaries)

| Tier | Code | Claim |
|------|------|-------|
| **A — Proven core** | MLS policy, capability model, process table, firewall verdicts | *Formally verified* (SPARK, 0 unproved VCs) |
| **B — Isolated periphery** | e1000e, NVMe, network stack | *Contained* — a compromise cannot reach tier A |
| **C — Scaffold** | packet-filter crypto, full firewall rules | *Not implemented in this build*, explicitly labelled |

Drivers (NVMe, e1000e, network stack) are **not proven** and are not claimed to be — hardware has no formal specification. They are isolated in separate domains instead.

> **Note on `schild_firewall`:** it is split across tiers — the packet **verdicts** (token-bucket rate limiter) are Tier A and proved, while the full **ruleset/crypto** is Tier C scaffold (not implemented). This is an intentional boundary, not a missing firewall.

Known upstream limitations (none in this codebase):

- **IOMMU (VT-d)** — experimental/flaky upstream (sporadic scheduling-context race on x86_64 MCS). DMA isolation is pending.
- **SMP** — `KernelMaxNumNodes` is forced to 1 on x86_64 **MCS** (upstream constraint).
- **x86_64 MCS** is formally verified **weaker than ARM MCS** (official upstream status).

## ARM64 port (branch `arm64`)

The **`arm64`** branch targets the **Raspberry Pi 4B** (BCM2711) — an seL4 **formally verified AArch64** platform (4× Cortex-A72, SMP, UART debug):

- Full QEMU cycle works: ELF loader → seL4 kernel → root task → UART output.
- **virtio-net in QEMU** — validated end-to-end: ARP → ICMP → DHCP → TCP/HTTP → TCP server → DNS, with a split-ring descriptor ring, IRQ routed through seL4 Notifications (blocking `seL4_Wait` on a waiter thread), and the driver + protocol stack running in an **isolated child domain** with its own CSpace.
- Toolchain: QEMU aarch64, `gcc/g++-aarch64-linux-gnu`, `gnat-aarch64`, `repo`, `protoc`, `dtc`.
- Raspberry Pi has **no SMMU**, so DMA isolation stays out of scope on that platform.

See [`src/schild_core/arm64/README.md`](src/schild_core/arm64/README.md).

## Build (x86_64)

**Quick start (Docker, no toolchain install):**

```bash
docker build -t schild-tcb .
docker run --rm -v "$PWD":/repo schild-tcb    # build + SPARK verify (green = "proof passed")
```

Requirements (native): GNAT (Ada/SPARK 2022) + gprbuild (Alire `gnat_native` 14.2.1 recommended), grub-mkrescue, QEMU.

```bash
cd src/schild_core

# Bare-metal kernel
./build.sh

# seL4 integration (Ada root task), QEMU
SEL4_PRIMARY=1 ./build.sh

# Formal verification
bash scripts/verify.sh          # root-task daemons, SPARK Level 4
bash scripts/prove_kernel.sh    # full kernel run (180 modules)

# Run in QEMU
SKIP_BUILD=1 SEL4_PRIMARY=0 bash scripts/run_tests.sh
```

## CI (GitHub Actions)

- **Push / PR to `master`** → `build` (bare-metal kernel + ISO) and `verify` (8 root-task proof units, SPARK Level 4) run automatically.
- **Manual** (`Actions` → `CI` → *Run workflow*) → the `prove-full` job runs the complete 180-module SPARK Level-4 proof (`scripts/prove_kernel.sh`) and uploads `obj/proof/report.txt` as an artifact.

## Contributing

Contributions and feedback are welcome — see [`CONTRIBUTING.md`](CONTRIBUTING.md) and the [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md). Security issues should be reported privately per [`SECURITY.md`](SECURITY.md).

## Documentation

- [`docs/GUIDE.md`](docs/GUIDE.md) — step-by-step tutorial (build → run → verify).
- [`docs/README.md`](docs/README.md) — documentation index & single source of truth.
- [`docs/GLOSSARY.md`](docs/GLOSSARY.md) — glossary (VC, Pre/Post, Tier A/B/C, Capability).
- [`docs/methodology/`](docs/methodology/) — the "AI-agent constitution" and worked case studies.
- [`PROJECT_PASSPORT.md`](PROJECT_PASSPORT.md) — project overview.
- [`docs/technical/ASSURANCE.md`](docs/technical/ASSURANCE.md) — assurance case & hardening roadmap.
- [`docs/technical/THREAT_MODEL.md`](docs/technical/THREAT_MODEL.md) — threat model & adversary model.
- [`docs/technical/ARCHITECTURE.md`](docs/technical/ARCHITECTURE.md) — technical data sheet.
- [`docs/technical/ROADMAP.md`](docs/technical/ROADMAP.md) — canonical "what's next".
- [`docs/technical/CHANGELOG.md`](docs/technical/CHANGELOG.md) — verified results only.
- [`docs/SCHILD_TCB_AUDIT_REPORT.md`](docs/SCHILD_TCB_AUDIT_REPORT.md) — internal technical review (author's self-assessment).

## License

The project's own code is licensed under **GPL-2.0-only** (see [`LICENSE`](LICENSE)). Third-party components are under their own licenses — see [`NOTICE.md`](NOTICE.md):

- seL4 microkernel — GPL-2.0-only (Data61/CSIRO)
- GNAT Runtime Library — GMGPL (GPL + runtime exception)

GPL-2.0-only is a deliberate choice: it ensures that derivative works remain open. For commercial use in closed-source products, a separate licensing agreement is possible — contact the author.

## Author

Alexander Irganov.

- Habr (RU): [Microkernel seL4, Ada/SPARK and formal verification](https://habr.com/ru/articles/1095314/) (16 Oct 2026)
- Habr (RU): [Доказано ≠ безопасно: как каскады ИИ-агентов заставили меня усилить модель угроз](https://habr.com/ru/articles/1102822/) (3 Nov 2026)
- vc.ru (RU): [«Зачем сварщику микроядро?»](https://vc.ru/id79615/3203908-zachem-svarshchiku-mikroyadro-sel4-i-proyekt-schild-tcb-na-ada-spark)
- Reddit (r/ada): [«I'm a 38-year-old welder…»](https://www.reddit.com/r/ada/s/XSFhtr1EzA)

© 2026 Alexander Irganov.

