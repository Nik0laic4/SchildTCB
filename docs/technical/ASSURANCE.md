# Schild TCB — Assurance Case & Hardening Roadmap

> Language: English (this file) | [Русский](./ASSURANCE.ru.md)

**Version:** v0.6  |  **Date:** 2026-11-15  |  **Status:** the assurance case and TCB are frozen (Tier A/B/C); "what's next" is in `ROADMAP.md`. §5 (phases) and §7 (log) are historical.
**Owner:** Ирганов А.Н.

---

## 1. Purpose

This document is the **general plan** (master plan) for turning Schild TCB from a
research prototype into a system whose security claims are **precise,
per-component, and mechanically checked** — instead of a broad "high-assurance"
label that is wider than the verified reality.

**Scope note.** This is a research prototype, not a product, not a Linux replacement, and not a certified system. It is an open reference architecture and methodology for building trusted computing bases on seL4. The value is in the approach, the assurance case, and the documented engineering decisions.

It defines:

1. the **trust model** (what we actually claim);
2. the **root causes** of the current proof/robustness gaps;
3. the **target layered architecture**;
4. a **phased roadmap** (Phase 1..4) with measurable exit criteria;
5. the **definition of done** for the verified system.

---

## 2. Trust model & assurance claims

Schild TCB has three kinds of code, and it must claim a different level of
assurance for each. The current failure mode is that these three are blurred.

| Tier | Code | Claim | Mechanism |
|------|------|-------|-----------|
| **A — Proven core** | MLS policy, capability model, process table, firewall verdicts | *Formally verified* (SPARK, 0 unproved VCs) | `SPARK_Mode => On` + contracts + loop invariants |
| **B — Isolated periphery** | e1000e, NVMe, network stack (ARP/IPv4/TCP/HTTP) | *Contained* (a compromise cannot reach tier A) | seL4 protection domains: own VSpace/CSpace, device caps, IPC-only |
| **C — Scaffold** | packet-filter crypto, full firewall rules, seL4 launch in the public build | *Not implemented in this build* | explicitly labelled, never claimed |

**Golden rule:** tier A may depend only on the **contracts** of abstraction
interfaces (tier B's specs), never on tier B bodies or on any hardware/driver.

### 2.1 Trusted Computing Base (frozen)

The **TCB** is the set of components whose correctness is required for the
tier-A guarantees. It splits into two honest halves:

**Verified TCB — `SPARK_Mode => On`, gnatprove level 4, 0 unproved:**
- `schild_cap_space` — capability model (mint / copy / retype / revoke / derivation)
- `schild_process_manager`, `schild_signals` — process table & MLS lifecycle
- `schild_server_security_policy` — role / level policy
- `schild_boot_runtime` — boot state machine & recovery
- `schild_firewall` — packet verdicts (token-bucket limiter)
- `schild_root_task` — boot-capability validation & frame allocation
- abstraction contracts: `Schild_Log` (`Global => null`), `Schild_Text`, `Schild_Sel4_Ipc`

**Unverified TCB — ring 0, runtime-tested only:**
- `boot.S` — 32-bit entry, identity paging, long-mode hand-off
- `runtime_stubs.c`, `interrupt_handlers.c`, `hw_io.c` — C runtime, IDT, MMIO
- **Local seL4 patches** (SMAP, object-zeroing, framebuffer, bootinfo-8k, max-num-drhu, load-image) — modify the formally verified kernel; reviewed but not re-proven. See [`SEL4_PATCHES_ANALYSIS.md`](SEL4_PATCHES_ANALYSIS.md) for the full analysis, risk classification, and minimization strategy. This is a real, acknowledged weakening of the upstream verification guarantee (AS8).

Everything else is **outside the TCB** and must be isolated (Phase 3): the
drivers and daemons run in their own **Tier B** protection domains —
**NetServer** (e1000e + TCP/IP), **FS daemon** (SchildFS + NVMe), **MLS server**
and **Config daemon** — all four on their own ELF via H87 Load_Elf
(v0.42/v0.46/v0.50/v0.51).
The FS daemon is Tier B, **not** part of the Verified TCB: `Schild_Schild_Fs` /
`Schild_Nvme` bodies are `SPARK_Mode => Off` and *contained* by seL4 (own
PML4/CSpace, NVMe BAR0 @0x620000), and `Persist_Audit_Log` reaches it over IPC
(`fs_ep`, op=5 Append) — never a direct tier-A→tier-B body call (H65).

### 2.2 Verified claims (frozen)

| Claim | Mechanical check | Result (2026-11-15) |
|-------|------------------|---------------------|
| Tier-A modules have no unproved VCs | `bash scripts/prove_kernel.sh` | `not-proved: 0` (canonical metrics — generated block below) |
| Level-4 root-task proof units prove (8: 1 daemon + 7 libraries/models) | `bash scripts/verify.sh` | "all verification conditions proved" (`not-proved: 0`) |
| Kernel builds clean | `SCHILD_PROFILE=public ./build.sh` | 185 objects, 0 errors |
| Boot chain works | `SKIP_BUILD=1 SEL4_PRIMARY=0 bash scripts/run_tests.sh` | PASS (Long Mode → e1000e → SMP → MLS → :80) |
| Network stack serves HTTP | QEMU + ThinkPad T580 | end-to-end (ARP → IPv4 → TCP → HTTP) |
| Fatal fault reboots, does not hang | `runtime_stubs.c` / `interrupt_handlers.c` | i8042 reset on all fatal handlers |

<!-- METRICS:START (generated by scripts/generate_metrics.py — do not edit) -->
**SPARK metrics** (commit `b874871`, 2026-11-23): **189 swept** · **179 in proof** (133 proved · 44 skipped · 2 no-output) · **10 scaffold excluded** · **0 unproved VCs**.

Accounting: `swept` = all modules; `in_proof` = `swept` − `scaffold_excluded`; `proved + skipped + no_output + not_proved` = `in_proof`. Source: `obj/proof/metrics.json`.
<!-- METRICS:END -->

> **Note (approximate count).** The `130 proved / 56 skipped` split (2026-11-01)
> is approximate: gnatprove's parallel prover (`-j8`) flips a few modules (e.g.
> `schild_execution_fabric`, `schild_sentinel`) between `PROVED` and
> out-of-proof across runs. The gate — `not-proved: 0` — is stable; the
> classifier (`scripts/classify_gnatprove.py`) is deterministic.

> **Note (public vs private build).** The numbers above are for the **public**
> profile (stubs). The **private** profile overlays full daemon bodies from
> `private/root_task/`; those are proved by `scripts/verify_private.sh`
> (`not-proved: 0`), except `Schild_Audit_Logger.Persist_Audit_Log` (`Off`, I/O)
> and the C shim `schild_net_runtime.c`. See `docs/README.md` §6.

---

## 3. Root-cause diagnosis (why the proof "leaks")

`prove_kernel.sh` reported `not-proved: 5` *before* Phase 1 (closed in Phase 1 —
see §7, `not-proved: 0`). The causes were **seams**,
not algorithm complexity:

| Module | Seam / cause |
|--------|--------------|
| `schild_boot_runtime` | manual `int→string` conversion with unprovable bounds (`Buf(1..10)`, `Pos` can underflow) + UART logging |
| `schild_cap_space` | `Cap_Revoke`/`Is_Derived_From` loops lack sufficient loop invariants |
| `schild_firewall` | UART logging seam + `Consume_Traffic_Token` (unannotated limiter) + `Block_Port` int→string bounds |
| `schild_process_manager` | UART logging seam + `goto Continue` (dead code) + unannotated `Signals` subprograms |
| `schild_root_task` | UART logging seam + seL4 IPC seam (`pragma Import` C syscall, no contract) |

The common **observability seam** is `Schild_Uart_Driver`, whose spec is
`SPARK_Mode => On` but declares **no `Global` contract** and whose body is
`SPARK_Mode => Off` (asm + `pragma Import`). SPARK therefore treats every
`Put_Line` as "may touch any global", poisoning flow analysis in every proven
module that logs.

**Conclusion:** the systemic fix is *not* five patches; it is (a) one
observability abstraction, (b) one bounded text helper, (c) loop invariants,
(d) removing `goto`, and (e) contracting the seL4 IPC seam.

---

## 4. Target architecture

```
┌────────────────────────────────────────────────────────────────┐
│  Tier A — PROVEN CORE      (SPARK_Mode => On, no I/O, no asm)   │
│  MLS, cap_space, process table, firewall verdicts               │
│  depends ONLY on abstraction contracts                          │
├────────────────────────────────────────────────────────────────┤
│  Tier B — ABSTRACTION INTERFACES (SPARK_Mode => On, contracted) │
│  Schild_Log (Global => null), Schild_Text (Image),             │
│  Schild_Sel4_Ipc (syscall contracts), Signals, Limiter          │
├────────────────────────────────────────────────────────────────┤
│  Tier C — PLATFORM        (SPARK_Mode => Off, hardened)         │
│  UART, framebuffer, MMIO, NVMe, e1000e, network stack           │
│  isolated under seL4; fuzz-tested; NOT claimed as proved        │
└────────────────────────────────────────────────────────────────┘
```

`Global => null` is the honest contract for observability: logging is a
side effect that **does not mutate security-relevant state**. The body is Off
and forwards to the platform UART driver.

---

## 5. Phase plan

> **Historical section.** The Phase 1–4 plan has been executed (see §7). Further
> work is canonically tracked in [`ROADMAP.md`](ROADMAP.md) (W1–W10); this section
> is kept as a record of the original plan.

### Phase 1 — Close the proof seams (target: `not-proved: 0` in tier A)

- Introduce `Schild_Log` (`Put_String`/`Put_Line`, `Global => null`).
- Introduce `Schild_Text.Image` — a provably-bounded `Unsigned/Integer → String`
  helper (replaces the hand-rolled, bound-buggy conversions).
- Route `schild_boot_runtime`, `schild_firewall`, `schild_process_manager`,
  `schild_root_task` off `Schild_Uart_Driver` onto `Schild_Log`/`Schild_Text`.
- Give `Schild_Sel4_Ipc` and the `Signals`/`Limiter` subprograms minimal
  `Global` contracts.
- Add loop invariants to `Cap_Revoke`/`Is_Derived_From`; remove `goto Continue`.

**Exit:** `prove_kernel.sh` → `not-proved: 0` for tier-A modules; `verify.sh`
passes; build + boot test green.

### Phase 2 — Honest bare-metal runtime (remove the "crutches")

- Replace the single 4 KB secondary-stack buffer (wrap-around, no lock) with
  per-core bounded stacks.
- Implement string concatenation correctly, or forbid runtime `&` (bounded
  buffers instead of the no-op stubs).
- Remove `malloc/free/calloc/realloc → NULL`; use fixed pre-allocated pools with
  compile-time `Storage_Size`.

**Exit:** no silent-memory-corruption primitives remain; `grep` for the stubs
returns zero; SMP stress boot is stable.

### Phase 3 — Isolate the periphery (the seL4 story)

- Run the network stack + drivers in their own protection domains (VSpace/CSpace
  + device caps), reachable only by IPC.
- A remote DoS in the network stack then breaks a *contained* domain, not the
  kernel.

**Status (2026-08-17): containment demonstrated (QEMU); SEL4_PRIMARY is the
verification artifact, standalone is the bare-metal artifact.** The
`SEL4_PRIMARY=1` build boots under QEMU: seL4 kernel + Ada root task + MLS
server + NetServer, with the NetServer holding its **own VSpace/CSpace** and
receiving e1000e IRQ via notification (`[S8.2] NetServer VSpace: OK`,
`[S8.3] e1000e IRQ: OK`). Note: `sel4_primary.iso` is a QEMU artifact — the
seL4 kernel's Multiboot2 header requests no framebuffer, and the T580 has no
serial port, so on real hardware the root task's serial log is invisible. The
ThinkPad T580 boots the **standalone** `schild_os.iso` (boot.S requests the GOP
framebuffer via Multiboot2 tag 5; full ECAM→NVMe→framebuffer→network chain).

**Crash-containment demonstrated.** The NetServer TCB is bound to a fault
*endpoint* (non-MCS seL4 rejects a notification fault handler as a CapFault),
minted (badge 0xE2) into the NetServer's own CSpace. A deliberate #PF injected
into the NetServer (`op=99`) is delivered by seL4 to that endpoint, the root
task catches it (`[FAULT] Caught fault — badge=0xE2`), and the core stays alive
(`[CONTAINMENT] core alive after fault`). Phase-3 exit criterion closed; the
regression markers for these three lines are enforced by `run_tests.sh`.

**MCS migration (2026-10-03).** The root task now runs on the **MCS** seL4
kernel: per-thread scheduling contexts (`SchedControl_ConfigureFlags` +
`SchedContext_Bind`) and reply objects, `ReplyRecv`/`Wait`/`NBWait` syscalls,
fault handlers set via `TCBSetSpace` (MCS, label 11). `run_tests.sh` passes all
12 markers. **Verification caveat:** x86_64 MCS is formally verified *weaker*
than ARM MCS in upstream seL4; this weaker baseline must be reflected in the
assurance argument until the x86_64 MCS proof catches up (see
`docs/technical/MCS_MIGRATION.md` §10).

### Phase 4 — Assurance case document (the honest label)

- Publish the tier matrix (Section 2) as the canonical claim.
- Every README claim points at a module + a mechanical check (gnatprove, seL4
  domain, fuzz corpus).
- Define and freeze the TCB.

**Exit:** no aggregate "high-assurance" claim without a per-component pointer.

---

## 6. Definition of done (measurable)

1. `prove_kernel.sh` → `not-proved: 0` **within tier A**.
2. Tier A contains no `pragma Import`, no `System.Machine_Code`, no MMIO address.
3. The network stack lives behind IPC and never shares a VSpace with tier A.
4. Scaffold items (firewall crypto, seL4 launch in public build) are labelled
   as such in README and CHANGELOG.
5. Every claim in this document is reproducible from a single command.

---

## 7. Progress log

> **Historical log (frozen at 2026-10-04).** Later verified results are in
> [`CHANGELOG.md`](CHANGELOG.md) and [`ROADMAP.md`](ROADMAP.md).

- 2026-08-16 — Document adopted. Phase 1 in progress: `Schild_Log` abstraction
  introduced; precise gnatprove diagnosis of the 5 not-proved modules launched.

- 2026-10-04 — **W4 complete: root-task orchestration formally proved.** The
  seL4 root task (`schild_root_task.adb`) flipped `SPARK_Mode => Off → On` and
  proved (54 checks, Level 4); `verify.gpr` now proves 7 daemons (MLS, Config,
  Audit, Boot, HM Model, Launch Model, Root Task). The syscall seam
  (`schild_sel4_syscall.ads`) is contracted (spec `On`, body `Off`); BootInfo is
  read as a value (C shim `schild_get_bootinfo_copy`). The proof caught 2 latent
  demo bugs (Rollback@`Validating`, Wait(`Fault_Slot`)=0). Proof gate hardened:
  `verify.sh` / `prove_kernel.sh` now fail on any `not proved` VC.

- 2026-10-04 — **W7 complete: storage isolated in the seL4 NetServer.** The NVMe
  driver + SchildFS run in the Ring 3 NetServer: ECAM discovery (+QEMU fallback),
  BAR0 mapped at `0x620000` (shared-untyped fix), `C_Addr → schild_dma_phys`
  (DMA offset), `Init_MMIO`; the full SchildFS write-path (Create→Write→
  Read-verify) is validated (`[NVFS] Read-back VERIFY OK`, QEMU 20/20).

### Precise diagnosis (gnatprove, level 4, 2026-08-16)

The dominant cause is **index/range/overflow discipline**, not the UART seam:

- `schild_cap_space`: `Cap_Index` is `0 .. 2**12-1` while the table is `0..63`,
  so every `Table (S)` indexing is unprovable; `Cap_Revoke`/`Is_Derived_From`
  loops lack invariants; `Depth + 1` can overflow.
- `schild_process_manager`: `Find_Process`/`Find_Free_Slot` return `Integer`
  (0 = sentinel), so `Table (Slot)` indexing is unprovable; `goto Continue`.
- `schild_boot_runtime`: hand-rolled `int→string` has unprovable bounds
  (`Buf(1..10)`, `Pos` underflow) + `Buf` may-be-uninitialized; `Attempts + 1`
  overflow.
- `schild_firewall`: `Total_Allowed/Dropped + 1` overflow (`Natural`); limiter
  precondition unproven; `Block_Port` int→string bounds.
- `schild_root_task`: `Unsigned_32 (Size)` range check; seL4 IPC seam.

**Structural fixes (Phase 1):** narrow index types to match the tables; add
loop invariants; one bounded `Image` text helper; bounded counters; contract
the seL4 IPC / limiter seams; remove `goto`. UART routing through `Schild_Log`
removes the remaining observational seam.

- 2026-08-16 — **Phase 1 complete**: `prove_kernel.sh` → `not-proved: 0`
  (183 modules; the 5 former NOT-PROVED modules now prove). `Schild_Log`
  (`Global => null`) + `Schild_Text.Image` abstractions introduced; cap_space /
  process_manager index types narrowed; limiter self-clamp; firewall/boot/
  root-task fixed.
- 2026-08-16 — **Phase 2 complete**: secondary stack is per-core bounded
  (xAPIC-ID indexed, 8 KB each, panic on overflow instead of wrap-around);
  `system__concat_*` implemented with copy semantics (no more no-op garbage);
  `malloc/calloc/realloc` panic loudly instead of silently returning NULL.
  Build 179 objects / 0 errors; boot test PASS.

- 2026-08-16 — **Phase 3 assessment**: `SEL4_PRIMARY=1` builds and boots
  (seL4 + Ada root task + MLS server + NetServer, NetServer in its own VSpace,
  e1000e IRQ via notification — `[S8.2]/[S8.3]` PASS). Crash-containment is the
  remaining gate.

- 2026-08-17 — **Phase 3 complete**: crash-containment demonstrated. Root
  cause of the stuck fault delivery was two-fold: (1) non-MCS seL4 rejects a
  *notification* fault handler (`sendFaultIPC` requires an endpoint with
  CanSend+CanGrant), so the fault notification was replaced by a fault
  *endpoint* minted into the NetServer CSpace; (2) the NetServer (priority 0)
  only runs while the root task (priority 255) blocks, so the containment test
  now replies-then-faults and the root task catches the fault with a blocking
  `Recv` on the fault endpoint. `run_tests.sh` enforces
  `[CONTAINMENT] injecting fault…` / `[FAULT] Caught fault` /
  `[CONTAINMENT] core alive after fault` — all PASS. Also fixed three latent
  root-task build defects (missing `rt_panic`, missing `schild_net_config.o`
  link, missing `schild_log_buf/len`) that had made `SEL4_PRIMARY=1` rely on a
  stale `root_task.elf`.

- 2026-08-17 — **T580 boot correction**: `sel4_primary.iso` is a QEMU artifact,
  not a bare-metal image. The seL4 kernel's Multiboot2 header
  (`src/arch/x86/multiboot.S`) requests no framebuffer tag, so GRUB prints
  `no console will be available to OS` and the root task's serial log is
  invisible on the T580 (no COM port). The T580 boots the standalone
  `schild_os.iso`, whose `boot.S` requests the GOP framebuffer (Multiboot2 tag
  5) and carries the full ECAM→NVMe→framebuffer→network chain. `build.sh`
  default restored to standalone (`SEL4_PRIMARY=0`); `sel4_primary.iso` is
  built explicitly with `SEL4_PRIMARY=1` for QEMU.

---

## 8. Reproducibility

Every claim in Section 2.2 is re-verifiable from a clean checkout:

```bash
cd src/schild_core
SCHILD_PROFILE=public ./build.sh                          # build (185 objects, 0 errors)
SKIP_BUILD=1 SEL4_PRIMARY=0 bash scripts/run_tests.sh      # boot smoke test
bash scripts/verify.sh                                      # Level-4 gnatprove (fails on unproved)
bash scripts/prove_kernel.sh                                # full SPARK sweep → not-proved: 0
```

---

## 9. Accepted residuals (2026-11-15)

| Risk | Attack scenario | Mitigation (today) | Blocking dependency |
|---|---|---|---|
| **C4** syscall seam (1475 lines SPARK_Off + C shims) | bug in the seam breaks Tier-A isolation (the trust root) | code review; seam is the trust root of every Tier-A claim | **C4 fuzzing** (planned, `C4_FUZZING_PLAN.md`) |
| **AS8** 7 local seL4 patches | patch regresses a proven kernel property | per-patch review; full analysis in `SEL4_PATCHES_ANALYSIS.md` | **upstream attempt** (framebuffer/bootinfo) |
| **C9** heartbeat detect-not-recover | ~~daemon hangs are detected but not auto-recovered~~ | `Health_Ok[D]=False` → boot-manager failover + **H90-A**: MCS timeout-fault → `Health_Monitor` restart | **mitigated (H90-A, 2026-11-20)** |
| **H112** MLS/Config in root CNode | ~~compromised MLS/Config signals `IRQ_Ntfn`/`Timeout_EP`/`Root_Fault_EP` (fake-fault)~~ | **mitigated (2026-11-19):** MLS/Config have their own CSpace (CNode 4128/4129) with only ep/reply/ping caps | — (closed) |
| **C8** boot counter not persistent | boot counter not yet read/written (NVMe deferred) | deferred (not active) | NVMe persistence + Tier-A counter store |
| **M20** `op=99` fault-injection compiled unconditionally | ~~attacker reaches the test-only fault path~~ | **mitigated (2026-11-20):** compiled out behind `#ifdef SCHILD_SELFTEST` (production default off) | — (closed) |
| **R23** MLS gate is communication-level only | non-root Top_Secret peer can `Fs_Delete("audit.log")` | **mitigated (2026-11-21):** per-file levels + operation-aware gate | — (closed) |
| **R24** root bypass at the caller | MLS enforcement is meaningless under root compromise | accepted — root is in the TCB | — (by design) |

### Residuals in detail

- **H107 / H88 policy (R23) — closed:** the MLS gate (`Authorize_IPC_Levels`) was communication-level (strict equal-clearance), not per-file and not per-operation. A non-root Top_Secret peer (e.g. `Audit_Logger`) could `Fs_Delete("audit.log")`; a lower-clearance domain could not even `Fs_Is_Mounted`. Implemented in v0.57: per-file levels (`Dir_Entry.Level/Owner`) + an operation-aware gate (`Authorize_File_Op`) — read→`Can_Read`, write→`Can_Write`, delete→owner-only, mount-control→any authenticated. Marker `[R23] Fs_Open write-down denied`.
- **R2 root bypass (R24):** root bypass is implemented at the caller side (`sender_role = 0` → the daemons skip the gate); `Authorize_IPC_Levels` is a pure equal-clearance predicate with no bypass branch. MLS enforcement is meaningless under root compromise — accepted (root is in the TCB).
- **M20 (test-only fault injection) — closed:** `op=98`/`op=99` is compiled out behind `#ifdef SCHILD_SELFTEST` (default off; `run_tests` sets `=1` for selftest). Daemon handlers and fault-write are preprocessor-removed; the Ada driver is gated by `schild_selftest_enabled()`. Production boot: no fault injection.
- **C8 (boot counter persistence, latent):** NVMe I/O is deferred (no `Read_Block`/`Write_Block` wired — `BOOT_COUNTER_DESIGN` §5), so C8 is not active. When NVMe persistence lands, the boot counter must be read by Tier A directly (option a), not via the Tier B NVMe driver — otherwise the golden rule breaks. Deferred indefinitely until IOMMU or a Tier A-controlled counter store.
- **C9 heartbeat (liveness-detect + H90-A recover):** the root task polls 4 per-domain ping notifications (badge-OR-safe — one object per domain, demux by slot) and updates `Last_Seen[D]` via RDTSC (HPET-calibrated `cycles/us`). Detects a hang (`Health_Ok[D]=False`) and, since H90-A, recovers: the FS daemon runs a sporadic SC (budget < period) after init-mount, so a hung busy-wait overruns its budget and raises `seL4_Fault_Timeout`; the root polls the shared `Timeout_EP` and calls `Health_Monitor` on the timeout (restart). RDTSC threshold assumes single-core / TSC-synchronized; on SMP with unsynchronized TSC, false positives are possible (current target is 1 core). Boot-manager `Health_Status` is renamed `NetServer_Alive`/`MLS_Alive`: "alive" = heartbeat liveness, **not** functional; the MLS functional probe (`Call_IPC(MLS_EP, op=2, target=4) → 1`) is gated on the heartbeat + throttled 5 s, but it is blocking (H90 covers the FS persist path; the MLS probe remains gated, not timeout-wrapped). Network functional probe (NIC link/RX/TX) remains pending. **Residual Д3:** the detect flow itself is runtime (tested via run_tests), not formally proved — SPARK reports the `Last_Seen`/`Health_Ok` writes as unused assignments in the infinite main loop; extracting the health cycle into a provable `schild_health_monitor` package is planned.
- **C4 (syscall seam):** Tier A security properties hold conditional on seam correctness, which is trusted, not proven (1475 lines SPARK_Off + C shims). This is the main residual of the Tier A claims.
- **AS8 (local seL4 patches):** 7 patches modify the formally verified kernel (SMAP, object-zeroing, framebuffer ×3, bootinfo-8k, max-num-drhu, load-image). Each is reviewed but not re-proven; the upstream verification guarantee transfers only partially. The full analysis, risk classification, and the architectural path to a clean upstream kernel are in [`SEL4_PATCHES_ANALYSIS.md`](SEL4_PATCHES_ANALYSIS.md). Accepted as a documented residual; minimization is tracked in `ROADMAP.md`.
- **H112 (MLS/Config CSpace not isolated) — mitigated (2026-11-19):** the MLS and Config daemons previously ran in the root CNode (`CNode_Slot=2`), not their own CSpace, so a compromised MLS/Config could `seL4_Signal` any notification in the root CSpace — `IRQ_Ntfn` (fake IRQ), `Timeout_EP` (fake budget overrun), `Root_Fault_EP` (fake domain fault). Fixed: each now has a 4-radix CNode (4128/4129) holding only the minted ep/reply/ping caps, and `TCB_Set_Fault_Handler` uses the own CSpace. The fake-fault vector is closed.



