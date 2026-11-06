# Schild TCB v0.22-pre — release notes (pre-release)

> Honest pre-release of a research prototype. NOT a certified system; every
> claim is per-component (see `ASSURANCE.md`, `THREAT_MODEL.md`).

## What it is

A formally verifiable core (**seL4** microkernel + **Ada/SPARK 2022**) with four
isolated Ring-3 daemons (MLS server, Config Daemon, NetServer, FS Daemon). This
release marks **"private functionally complete"**: the private profile persists
the audit log through the FS daemon over IPC.

## What's new since v0.1.0

- **FS daemon** (Ring 3): NVMe + SchildFS moved out of NetServer into a dedicated
  daemon (own PML4/CSpace, NVMe BAR0 @0x620000) — H86.
- **Audit persistence over IPC**: `Persist_Audit_Log` → `fs_ep` (op=5 Append) —
  H65/H82 CLOSED; the FS body no longer executes in the root-task VSpace.
- **H72 append-mode audit log**: `audit.log` grows across boots instead of being
  overwritten (`Write_File` extend + chunked persist ≤4 KB).
- **Containment for all four daemons** (MLS, Config, NetServer, FS) — H93.
- **CI**: `verify_private.sh` in the push gate (H89); full `SEL4_PRIMARY=1`
  build+run as a manual job (H68b).

## Key results (mechanically checkable)

- Bare-metal build: **182 objects, 0 errors**.
- seL4 build (public + private): `Done`, no `[RT] ERROR`.
- SPARK: `verify.sh` (8 proof units = 1 daemon + 7 libraries/models) and
  `verify_private.sh` (full private bodies) — all VCs proved; full sweep
  **186 modules, 130 proved / 56 skipped** (`not-proved: 0`).
- QEMU: `run_tests.sh` **23/23** markers in both profiles.

## Honest limitations (residual risks)

1. **Shared image RW (H87)** — daemons share one ELF `.bss`; an OOB write from
   one daemon can corrupt the root task's globals. ELF loader → v0.3.0.
2. **Syscall seam (AS6)** — `schild_sel4_syscall.adb` 1475 lines `Off`, trusted
   not proven; a seam bug = Ring-0 escape.
3. **Ring-0 C (C1)** — `runtime_stubs.c` / `interrupt_handlers.c` / `hw_io.c` are
   trusted, runtime-tested only.
4. **MLS enforcement (H88)** — `Role_FS_Server = Top_Secret` is registered, but
   IPC carries no level; cross-daemon read-up/write-down is held by discipline,
   not by a gate.
5. **Persist timeout (H90)** — `Persist_Audit_Log` blocks on the FS `Call`; no
   timeout is implemented.
6. **No DMA isolation** — IOMMU/VT-d upstream-blocked (x86_64 MCS); Pi 4 has no SMMU.
7. **No signed boot / HWRoT**; **patched seL4** (upstream proof transfers only partially).
8. **PID reuse (CVE-2026-SCHILD-02 #005)** — noted, not mitigated.

## Reproduction

```bash
cd src/schild_core
SCHILD_PROFILE=public ./build.sh                         # bare-metal (182 objects)
SEL4_PRIMARY=1 SCHILD_PROFILE=public ./build.sh          # seL4 root task
SEL4_PRIMARY=1 SCHILD_PROFILE=private ./build.sh         # full daemon bodies
bash scripts/verify.sh                                   # 8 proof units
bash scripts/verify_private.sh                           # private bodies
SKIP_BUILD=1 SEL4_PRIMARY=1 SCHILD_PROFILE=public bash scripts/run_tests.sh  # 23/23
```
