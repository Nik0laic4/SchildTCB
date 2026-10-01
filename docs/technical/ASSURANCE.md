# Schild TCB — Assurance Case & Hardening Roadmap

**Version:** v0.4  |  **Date:** 2026-08-17  |  **Status:** Phases 1-2, 4 complete; Phase 3 containment demonstrated (QEMU)
**Owner:** Ирганов А.Н.

---

## 1. Purpose

This document is the **general plan** (генплан) for turning Schild TCB from a
research prototype into a system whose security claims are **precise,
per-component, and mechanically checked** — instead of a broad "high-assurance"
label that is wider than the verified reality.

It defines:

1. the **trust model** (what we actually claim);
2. the **root causes** of the current proof/robustness gaps;
3. the **target layered architecture**;
4. a **phased roadmap** (Phase 1..4) with measurable exit criteria;
5. the **definition of done** for the "engineering masterpiece".

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

Everything else — NVMe / e1000e / ARP / IPv4 / TCP / HTTP — is **outside the
TCB** and must be isolated (Phase 3).

### 2.2 Verified claims (frozen)

| Claim | Mechanical check | Result (2026-08-16) |
|-------|------------------|---------------------|
| Tier-A modules have no unproved VCs | `bash scripts/prove_kernel.sh` | `not-proved: 0` (183 modules) |
| Level-4 root-task daemons prove | `bash scripts/verify.sh` | "all verification conditions proved" |
| Kernel builds clean | `SCHILD_PROFILE=public ./build.sh` | 179 objects, 0 errors |
| Boot chain works | `SKIP_BUILD=1 SEL4_PRIMARY=0 bash scripts/run_tests.sh` | PASS (Long Mode → e1000e → SMP → MLS → :80) |
| Network stack serves HTTP | QEMU + ThinkPad T580 | end-to-end (ARP → IPv4 → TCP → HTTP) |
| Fatal fault reboots, does not hang | `runtime_stubs.c` / `interrupt_handlers.c` | i8042 reset on all fatal handlers |

---

## 3. Root-cause diagnosis (why the proof "leaks")

`prove_kernel.sh` currently reports `not-proved: 5`. The causes are **seams**,
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

- 2026-08-16 — Document adopted. Phase 1 in progress: `Schild_Log` abstraction
  introduced; precise gnatprove diagnosis of the 5 not-proved modules launched.

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
SCHILD_PROFILE=public ./build.sh                          # build (179 objects, 0 errors)
SKIP_BUILD=1 SEL4_PRIMARY=0 bash scripts/run_tests.sh      # boot smoke test
bash scripts/verify.sh                                      # Level-4 gnatprove (fails on unproved)
bash scripts/prove_kernel.sh                                # full SPARK sweep → not-proved: 0
```



