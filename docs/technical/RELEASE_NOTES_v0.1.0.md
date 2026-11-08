# Schild TCB v0.1.0 — release notes (pre-release)

> Honest pre-release of a research prototype. NOT a certified system; every
> claim is per-component (see `docs/technical/ASSURANCE.md`, `THREAT_MODEL.md`).
> For the GitHub "Release notes" field.

## What it is

A research prototype of a Trusted Computing Base (TCB): a formally verifiable
core (**seL4** microkernel + **Ada/SPARK 2022**) with an isolated-peripheral
environment. Two artifacts:

- **bare-metal OS** in Ada (bootloader, NVMe, e1000e, TCP/IP, HTTP) — runs on a
  ThinkPad T580 and in QEMU;
- **seL4 root task** + daemons, with network/storage isolated in Ring 3.

## Key results (mechanically checkable)

- 187 kernel modules swept at **SPARK Level 4** with **0 unproved VCs**; ~130 proved / ~56 out-of-proof (`SPARK_Mode => Off` drivers/platform code).
- 8 proof units proved (`verify.sh` — 1 daemon + 7 libraries/models); full (private) bodies — `verify_private.sh`.
- MLS Bell-LaPadula (5 levels) proved in `schild_server_security_policy`, `schild_process_manager`, `schild_file_descriptors`.
- Network: ARP/IPv4/ICMP/UDP/TCP parsers proved at L4 (W10); CBC chaining, max-priority scheduler + ARINC-653 MTF (W11).
- Boots on a ThinkPad T580 (32 GB) and in QEMU; ARM64 (Raspberry Pi 4B) port in progress.

## Honest limitations (residual risks, THREAT_MODEL §8)

1. **No DMA isolation** (IOMMU/VT-d is upstream-experimental; the Pi 4 has no SMMU). "Isolation" is process-level, not bus-level.
2. **Unproven C code** (`net_test.c`, `sel4_mmio.c`, `runtime_stubs.c`, …) — memory-unsafe, backed only by containment.
3. **Contracts prove the property, not the full end-to-end scenario** (W11 partially closed: CBC / scheduler / MLS).
4. **No signed boot / HWRoT** — SHA-256 detects corruption, not malice.
5. **x86_64 MCS** is formally verified weaker than ARM MCS (upstream status).
6. **Patched seL4** — the upstream proof transfers only partially.
7. **PID reuse** (CVE-2026-SCHILD-02 #005) — noted, not mitigated.
8. **ARM64** — virtio-net validated in QEMU; GENET (Pi 4) blocked on hardware availability.

## Reproduction

Step-by-step tutorial (build → run → verify): [`docs/GUIDE.md`](docs/GUIDE.md).

```bash
cd src/schild_core
./build.sh                          # bare-metal (183 objects, 0 errors)
bash scripts/verify.sh              # 8 proof units (not-proved: 0)
bash scripts/prove_kernel.sh        # full 187-module sweep (~10 min)
# Docker: docker build -t schild-tcb . && docker run --rm -v "$PWD":/repo schild-tcb
```

