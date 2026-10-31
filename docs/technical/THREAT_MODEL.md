# Schild TCB — Threat Model

**Version:** v1.0.0-pre (working draft)
**Date:** 2026-10-31
**Owner:** Ирганов А.Н.
**Status:** living document. Aligned with [`ASSURANCE.md`](ASSURANCE.md) (trust model),
[`SECURITY.md`](SECURITY.md) (per-component claims), [`ARCHITECTURE.md`](ARCHITECTURE.md)
(data sheet). This document is the **input** to contract strengthening — every
Tier-A security property in §7 must eventually become a SPARK contract.

> **Honest scope note.** This is a threat model for a research prototype. It
> follows the *structure* of a DO-326A security risk assessment without claiming
> certification conformance. The goal is precise, per-component, mechanically
> checkable claims — not a broad "high-assurance" label.

---

## 1. Purpose

This document answers four questions, in order:

1. **What do we protect?** (§2 Assets)
2. **Who attacks, and how capable are they?** (§3 Adversary model)
3. **What stops them?** (§4 Trust boundaries, §5 Assumptions, §7 mapping)
4. **What remains after all defenses?** (§8 Residual risks)

It also records **what we take on faith** (§9 seL4 axiomatics) and **how the
remaining gaps are closed** (§10 contract strengthening).

### 1.1 Relationship to standards

| Artifact | Standard | Status |
|----------|----------|--------|
| This threat model (security risk assessment) | DO-326A / DO-356A | structure followed; **not** a cert artifact |
| SPARK proofs | DO-333 (formal methods supplement) | in progress; Level 4 on the proven core |
| Safety criticality / DAL | DO-178C | **not targeted** — a solo-dev research prototype does not claim DO-178 conformance |

---

## 2. Assets (A1–A6)

| Asset | What it is | Security property that matters | Tier |
|-------|-----------|-------------------------------|------|
| **A1 — Proven core** | MLS policy, capability model, process table, firewall verdicts | confidentiality + integrity (mathematically enforced) | A |
| **A2 — Isolated periphery** | NetServer: e1000e / NVMe / TCP-IP stack (ARP, IPv4, TCP, HTTP) | availability via *containment* — its compromise must not propagate | B |
| **A3 — TCB runtime** | seL4 kernel + Ada root task + trusted seams (syscall shim, C runtime, `boot.S`) | integrity of the whole system | ring 0 + root |
| **A4 — Audit log** | `Schild_Audit_Logger` ring buffer with severity filter | integrity + non-repudiation | A |
| **A5 — Boot & update path** | A/B images, `Schild_Boot_Manager`, boot counter, rescue slot | integrity + availability | (gap — see §8) |
| **A6 — Platform & devices** | CPU, MMU, APIC/GIC, NIC, NVMe, DMA engines | availability + integrity | (DMA out of scope) |

Each asset is the *reason* an adversary class exists in §3. The mapping
"asset → adversary → defense → check" is closed in §7.

## 3. Adversary model

Four adversary **classes** (P1–P4) define *who* is in scope. One **capability
axis** (the AI-agent cascade) applies on top of P1–P4 and defines *how capable*
the attacker is — it is **not** a fifth class.

### 3.1 Classes in scope

| Class | Description | In scope? |
|-------|-------------|-----------|
| **P1 — Remote network attacker** | Reaches only the exposed surface: the TCP/IP stack (HTTP server). No credentials, no local access. | yes — primary |
| **P2 — Compromised Tier-B domain** | Already has a foothold inside an isolated driver/stack (a bug was exploited). Tries to reach the core or other domains. | yes — the "containment" adversary |
| **P3 — Malicious / compromised peripheral** | A DMA-capable device (NIC, NVMe) that lies or writes memory directly. | analyzed, **not fully mitigated** (§8) |
| **P4 — Attacker with local build/deploy access** | Can replace images, write update slots, or flip the boot counter. | partially — rollback/malicious update (§8); full supply-chain **out of scope** |

### 3.2 The AI-agent cascade (capability axis, applies to P1–P4)

Autonomous AI agents (single- or multi-agent "cascades") do not create a new
attack surface — they **multiply the capability** of existing classes by
lowering cost, time, and skill to near zero, and by chaining multiple bugs into
one exploit.

Consequences that shape this threat model:

1. **Every unproven line is assumed already exploitable.** Memory-safety and
   logic bugs in C code (`net_test.c`, `sel4_mmio.c`, `sel4_stubs.c`,
   `runtime_stubs.c`) and `SPARK_Mode => Off` Ada drivers must be treated as
   found-and-weaponized. "Nobody will find this" is not a valid assumption.
2. **Obscurity is dead; machine-checkable defenses are not.** Formal proof and
   kernel-enforced isolation are the only controls that do *not* degrade as the
   attacker gets faster and smarter. This is exactly the Tier A / Tier B split.
3. **Reactive patching is too slow.** For a prototype the response must be
   *architectural* (isolate the unproven) rather than *reactive* (patch after
   exploit).

**Net effect:** the AI axis *strengthens* the argument for (a) keeping
`pragma Assume` at 0, (b) proving the security properties, not just the
abstraction, and (c) treating the Tier-B containment boundary as the primary
control for all unproven code.

---

## 4. Trust boundaries

| # | Boundary | What crosses it | Enforced by |
|---|----------|-----------------|-------------|
| **TB1** | ring 0 (seL4 kernel) ↔ ring 3 (root task + domains) | syscall ABI only | seL4 kernel (VSpace / CSpace / capabilities) |
| **TB2** | root task ↔ NetServer / MLS server | IPC messages + endpoint badges + notifications | seL4 capabilities (`Send`/`Recv`/`Grant` rights), badge checks |
| **TB3** | Tier A ↔ Tier B | **contracts only** (the golden rule) | architecture: Tier A depends on Tier-B *specs*, never Tier-B *bodies* |
| **TB4** | platform ↔ everything | MMIO / DMA / interrupts | **weakest** — no IOMMU/VT-d today (see §8) |

TB1–TB3 are real and mechanically checked. TB4 is the open boundary: without
DMA isolation, a malicious device (P3) can read/write any physical memory,
including the kernel and the root task.

## 5. Assumptions (each with its violation consequence)

| # | Assumption | What happens if it is violated |
|---|-----------|-------------------------------|
| **AS1** | The seL4 kernel (upstream + local patches) is correct and enforces its capability/VSpace model. | Total compromise — nothing above it survives. This is the root of trust. |
| **AS2** | The hardware behaves per spec (CPU, MMU, APIC/GIC, no rowhammer/glitch-class attacks). | All proof and isolation guarantees are void (physical/side-channel, out of scope §6). |
| **AS3** | The toolchain (GNAT, GCC) and the provers (Alt-Ergo/CVC5/Z3) are sound. | The SPARK proof is void. |
| **AS4** | The boot chain before the kernel (Multiboot2 loader / firmware) is not attacker-controlled. | An attacker replaces the kernel or root task before boot — nothing can recover. |
| **AS5** | The syscall seam (`Schild_Sel4_Syscall` + C shims) correctly encodes the seL4 ABI (syscall numbers, message-info encoding, MR/cap slots). | A seam bug lets a domain escape its CSpace/VSpace. Runtime-tested, not proven (§9). |

Each assumption is the *price* of the corresponding claim. If one is violated,
the claims of §7 that depend on it are void — this is stated, not hidden.

---

## 6. Out of scope (with justification)

| Item | Why it is out of scope |
|------|------------------------|
| DMA isolation (IOMMU/VT-d) | upstream x86_64 MCS is experimental/flaky; Raspberry Pi 4 has no SMMU. **Highest residual risk (§8).** |
| SMP on x86_64 MCS | upstream forces `KernelMaxNumNodes = 1` on x86_64 MCS. |
| Physical attacks (probe, glitch, cold boot, rowhammer) | no threat model for silicon; assumption AS2. |
| Side-channels (Spectre/Meltdown/…) | IBRS is *attempted* at boot, not a full mitigation. |
| Supply chain (compiler, hardware, upstream seL4) | out of reach for a solo prototype; assumption AS3. |
| Availability/DoS of a Tier-B domain itself | by design, containment means the *core* survives — not that the isolated domain is always up. |
| Full DO-178C safety certification | not a solo-developer target (see §1.1). |

---

## 7. Threat → mechanism → tier → mechanical check

This is the core mapping. Each row is a claim that must stay true; the
"check" column is how it is enforced or demonstrated.

| # | Threat (adversary) | Defense mechanism | Tier | Mechanical check |
|---|--------------------|-------------------|------|------------------|
| T1 | P1/P5 remote memory-safety exploit of the TCP/UDP parser (incl. AI-generated UAF/overflow) | seL4 protection domain (own VSpace/CSpace) + IPC-only + fault endpoint | B | `[CONTAINMENT] core alive after fault` in `run_tests.sh` |
| T2 | P2 compromised domain escalates to Tier A via IPC | capability model: mint / copy / retype / revoke / derivation + endpoint badges | A | SPARK Level 4 on `schild_cap_space` (`prove_kernel.sh`) |
| T3 | P1/P2 MLS bypass (read-up / write-down / control-up) | `Schild_MLS_Policy` + `schild_process_manager` level checks | A | `verify.sh` / `prove_kernel.sh`; QEMU MLS 8/8 |
| T4 | P2/P5 uninitialized read / integer overflow / out-of-bounds in the core | SPARK: no uninit reads, bounded ranges, narrowed index types (Phase-1 fixes) | A | `prove_kernel.sh` → `not-proved: 0` |
| T5 | P2 hangs the root task (availability) | MCS CPU budgets + fault timeouts | A/B | `seL4_Fault_Timeout` (QEMU MCS test) |
| T6 | P3 DMA write from a malicious NIC/NVMe | **none today** (no IOMMU) | — | residual risk (§8) |
| T7 | P4 rollback / malicious slot update | `Schild_Boot_Manager` SHA-256 (corruption detection only) | — | residual risk — no signed boot (§8) |
| T8 | P1/P5 exploit of the C shims/stack (`net_test.c`, `sel4_mmio.c`, `runtime_stubs.c`) | **no memory safety** — containment is the only backstop | B | `[CONTAINMENT] core alive after fault` |
| T9 | P4/P5 supply-chain (poisoned upstream/toolchain) | none | — | out of scope (§6) |

**Reading note:** T1 and T8 are the same defense for the same reason — the
network stack (Ada `SPARK_Mode => Off` on x86_64, C on ARM64) is **not** memory
safe. The only thing that stops a machine-speed AI exploit from reaching the
core is the Tier-B isolation boundary (TB2/TB3), not memory safety. T2–T4 are
the *only* rows where the defense is formal proof rather than isolation.

## 8. Residual risks (honest, after all mechanisms)

These are the risks that remain even when every §7 check is green:

1. **No DMA isolation (highest).** A malicious DMA device (P3) can read/write
   arbitrary physical memory, including the kernel and root task. IOMMU/VT-d is
   pending upstream; Raspberry Pi 4 has no SMMU. Until then, "isolated
   periphery" means *process* isolation, not *bus* isolation.
2. **Unproven C code is assumed exploitable.** `net_test.c`, `sel4_mmio.c`,
   `sel4_stubs.c`, `runtime_stubs.c`, `interrupt_handlers.c`, `hw_io.c` are
   memory-unsafe and not in the proof set. Containment (T8) is the only
   backstop.
3. **Contracts prove the abstraction, not yet the full security property.**
   This is the *known* gap the next work phase closes (§10). Today "proved"
   means "the module spec is proved", and the spec may be weaker than the
   end-to-end security property (e.g. "no read-up across *all* IPC paths").
4. **No signed boot / hardware root of trust.** `Schild_Boot_Manager` SHA-256
   detects *corruption*, not *malice*: an attacker who can write the update slot
   (P4) can also write a valid hash. Rollback and malicious-update remain open.
5. **x86_64 MCS is formally verified weaker than ARM MCS** (upstream status).
6. **Patched seL4.** The local patches modify a formally verified kernel; the
   upstream proof transfers only partially (§9).
7. **Watchdog/DoS.** A hardware watchdog (future work) recovers from hangs but
   is itself a DoS amplifier if an attacker can trigger hangs; it is a last
   resort *after* containment, not a substitute for it.

---

## 9. seL4 axiomatics (what is taken on faith)

The following are **trusted, not re-proven**, and must be listed explicitly:

- **Upstream seL4 kernel correctness.** seL4 has a machine-checked
  functional-correctness proof (strongest for the verified ARM configuration;
  x86_64 MCS is weaker — upstream). We accept this as the root of trust.
- **Local patches.** `patches/` contains kernel modifications (`seL4-smap.patch`,
  `seL4-object-zeroing.patch`, `seL4-framebuffer*.patch` (×3),
  `seL4-max-num-drhu.patch`, `seL4-bootinfo-8k-untyped.patch`).
  These alter the verified kernel; they are **reviewed but not re-proven**, so
  the transferred guarantee is partial. This is a real, acknowledged weakening.
- **The syscall seam.** `Schild_Sel4_Syscall` (spec `On`, body `Off`) and the C
  shims encode the seL4 ABI (syscall numbers, message-info layout, MR/cap
  slots). The mapping from Ada contracts to the actual ABI is trusted and
  runtime-tested, not proven.
- **The C runtime and entry.** `runtime_stubs.c`, `interrupt_handlers.c`,
  `hw_io.c`, `boot.S` are ring-0 trusted code, runtime-tested only.

Any future work that touches these seams must update this section.

---

## 10. From threat model to stronger contracts (next work)

This document is the **input** to the contract-strengthening phase. The method:

1. For each Tier-A row in §7 (T2–T4), derive the **exact** security property.
   Examples: "a capability is never minted into a slot without a valid parent",
   "no IPC crosses a level boundary downward", "no buffer index escapes its
   declared range".
2. Re-express that property as SPARK contracts (`Pre`/`Post`/`Global` +
   loop invariants) and prove at Level 4.
3. **Anti-strangling rule.** `Pre` must accept *all* legitimate inputs; `Post`
   states the security property. *Liveness* — that legitimate data still flows —
   is validated by runtime tests (QEMU 18/18, KAT), not by proof.
4. **No vacuity.** A `Post => True` or an impossible `Pre` proves nothing and is
   rejected. gnatprove vacuity checks are on.
5. **No escape hatches.** Keep `pragma Assume` = 0 and no `pragma Annotate`
   suppression (current state: both are 0). If a seam genuinely cannot be
   proven, record it here as a trusted axiomatic (§9), not as a hidden `Assume`.

---

## 11. References

- [`ASSURANCE.md`](ASSURANCE.md) — trust model, TCB split, phased hardening roadmap.
- [`SECURITY.md`](SECURITY.md) — per-component claims, MLS rules, hardware countermeasures, audit history.
- [`ARCHITECTURE.md`](ARCHITECTURE.md) — data sheet, architecture diagram, syscall ABI.
- [`SEL4_INTEGRATION.md`](SEL4_INTEGRATION.md) — seL4 integration history (Stage 5–8).
- [`MCS_MIGRATION.md`](MCS_MIGRATION.md) — MCS labels, ABI, fault/timeout details.
- [`RING3_NETWORK_MIGRATION.md`](RING3_NETWORK_MIGRATION.md) — NetServer isolation details.
- [`ROADMAP.md`](ROADMAP.md) — work order (W1–W7) and out-of-scope notes.
- [`DEVELOPMENT_VECTORS.md`](DEVELOPMENT_VECTORS.md) — reference codebases and DO-333 prep.
- [`security/CVE-2026-SCHILD-01.md`](security/CVE-2026-SCHILD-01.md), [`security/CVE-2026-SCHILD-02.md`](security/CVE-2026-SCHILD-02.md) — past audit findings (all fixed).



