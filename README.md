# Schild TCB

A formally verified **Trusted Computing Base (TCB)** and isolated-peripheral environment, built in **Ada/SPARK 2022** on top of the **seL4 microkernel**.

[![License: GPL-2.0-only](https://img.shields.io/badge/License-GPL--2.0--only-blue.svg)](LICENSE)
[![SPARK Level 4](https://img.shields.io/badge/SPARK-Level_4-not--proved:0-green)](docs/technical/ASSURANCE.md)

---

## What is this

Schild TCB is a research prototype of a microkernel-based trusted computing base. It is two artifacts, not one:

1. **A bare-metal OS** written from scratch in Ada — bootloader, NVMe driver, e1000e NIC driver, TCP/IP stack, HTTP server. Runs on a ThinkPad T580 and in QEMU. Answers *"does it work"*.
2. **An seL4-based artifact** — the microkernel is upstream (unmodified, formally verified), and the contribution is an Ada/SPARK **root task** plus several daemons. Network and storage run **isolated in Ring 3** processes, communicating over IPC. Answers *"is it proven"*.

## Highlights

- **Formal verification** — 185 kernel modules verified at **SPARK Level 4** (`gnatprove --level=4 --mode=all`), result **`not-proved: 0`**. 7 root-task daemons (MLS policy, config daemon, audit logger, A/B boot manager, HM model, launch model, root task) are also proven.
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

Known upstream limitations (none in this codebase):

- **IOMMU (VT-d)** — experimental/flaky upstream (sporadic scheduling-context race on x86_64 MCS). DMA isolation is pending.
- **SMP** — `KernelMaxNumNodes` is forced to 1 on x86_64 **MCS** (upstream constraint).
- **x86_64 MCS** is formally verified **weaker than ARM MCS** (official upstream status).

## ARM64 port (branch `arm64`)

The **`arm64`** branch targets the **Raspberry Pi 4B** (BCM2711) — an seL4 **formally verified AArch64** platform (4× Cortex-A72, SMP, UART debug):

- Full QEMU cycle works: ELF loader → seL4 kernel → root task → UART output.
- Toolchain: QEMU aarch64, `gcc/g++-aarch64-linux-gnu`, `gnat-aarch64`, `repo`, `protoc`, `dtc`.
- Raspberry Pi has **no SMMU**, so DMA isolation stays out of scope on that platform.

See [`src/schild_core/arm64/README.md`](src/schild_core/arm64/README.md).

## Build (x86_64)

Requirements: GNAT (Ada/SPARK 2022) + gprbuild (Alire `gnat_native` 14.2.1 recommended), grub-mkrescue, QEMU.

```bash
cd src/schild_core

# Bare-metal kernel
./build.sh

# seL4 integration (Ada root task), QEMU
SEL4_PRIMARY=1 ./build.sh

# Formal verification
bash scripts/verify.sh          # root-task daemons, SPARK Level 4
bash scripts/prove_kernel.sh    # full kernel run (185 modules)

# Run in QEMU
SKIP_BUILD=1 SEL4_PRIMARY=0 bash scripts/run_tests.sh
```

## Documentation

- [`PROJECT_PASSPORT.md`](PROJECT_PASSPORT.md) — project overview.
- [`docs/technical/ASSURANCE.md`](docs/technical/ASSURANCE.md) — assurance case & hardening roadmap.
- [`docs/technical/ARCHITECTURE.md`](docs/technical/ARCHITECTURE.md) — technical data sheet.
- [`docs/technical/ROADMAP.md`](docs/technical/ROADMAP.md) — canonical "what's next".
- [`docs/technical/CHANGELOG.md`](docs/technical/CHANGELOG.md) — verified results only.
- [`docs/SCHILD_TCB_AUDIT_REPORT.md`](docs/SCHILD_TCB_AUDIT_REPORT.md) — independent technical review.

## License

The project's own code is licensed under **GPL-2.0-only** (see [`LICENSE`](LICENSE)). Third-party components are under their own licenses — see [`NOTICE.md`](NOTICE.md):

- seL4 microkernel — GPL-2.0-only (Data61/CSIRO)
- GNAT Runtime Library — GMGPL (GPL + runtime exception)

## Author

Alexander Irganov.

- Habr (RU): [«Микроядро seL4, Ada/SPARK и 185 модулей: разбор проекта»](https://habr.com/ru/articles/1095314/)
- vc.ru (RU): [«Зачем сварщику микроядро?»](https://vc.ru/id79615/3203908-zachem-svarshchiku-mikroyadro-sel4-i-proyekt-schild-tcb-na-ada-spark)
- Reddit (r/ada): [«I'm a 38-year-old welder…»](https://www.reddit.com/r/ada/s/XSFhtr1EzA)

© 2026 Alexander Irganov.

