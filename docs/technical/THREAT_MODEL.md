# Schild TCB — Threat Model

**Version:** v1.1.0-audit (§12 supersedes conflicts in §3-§11 until inline merge)
**Date:** 2026-11-03
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
| **A5 — Boot & update path** | A/B images, `Schild_Boot_Manager`, boot counter, rescue slot | integrity + availability | lockout ✅ (W9.1); integrity gap — no signed boot (§8) |
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
| T1 | P1 (+AI) remote memory-safety exploit of the TCP/UDP parser (incl. AI-generated UAF/overflow) | **SPARK Level 4 on the parsers** (`Parse_Tcp`/`Parse_Udp`/`Parse_Arp`/`Parse_Ipv4`/`Validate_Tcp_Checksum`, all `On`) + seL4 protection domain + fault endpoint | A + B | `prove_kernel.sh` (`not-proved: 0`) + `[CONTAINMENT] core alive after fault` |
| T2 | P2 compromised domain escalates to Tier A via IPC | capability model: mint / copy / retype / revoke / derivation + endpoint badges | A | SPARK Level 4 on `schild_cap_space` (`prove_kernel.sh`) |
| T3 | P1/P2 MLS bypass (read-up / write-down / control-up) | `Schild_MLS_Policy` + `schild_process_manager` level checks | A | `verify.sh` / `prove_kernel.sh`; QEMU MLS 8/8 |
| T4 | P2 (+AI) uninitialized read / integer overflow / out-of-bounds in the core | SPARK: no uninit reads, bounded ranges, narrowed index types (Phase-1 fixes) | A | `prove_kernel.sh` → `not-proved: 0` |
| T5 | P2 hangs the root task (availability) | MCS CPU budgets + fault timeouts | A/B | `seL4_Fault_Timeout` (QEMU MCS test) |
| T6 | P3 DMA write from a malicious NIC/NVMe | **none today** (no IOMMU) | — | residual risk (§8) |
| T7 | P4 rollback / malicious slot update | `Schild_Boot_Manager` SHA-256 + boot-counter lockout (bounded retries → slot lock) | — | residual risk — no signed boot (§8) |
| T8 | P1 (+AI) exploit of the C shims/stack (`net_test.c`, `sel4_mmio.c`, `runtime_stubs.c`) | **no memory safety** — containment is the only backstop | B | `[CONTAINMENT] core alive after fault` |
| T9 | P4 (+AI) supply-chain (poisoned upstream/toolchain) | none | — | out of scope (§6) |

**Reading note:** T1's network parsers (ARP / IPv4 / ICMP / UDP / TCP) are now
**formally memory-safe** — SPARK Level 4, `not-proved: 0` (W10). The C shims and
drivers (`net_test.c`, `sel4_mmio.c`, `e1000e`, `nvme`) remain **not** memory
safe — for those (T8) containment is the only backstop. T2–T4 are formal proof;
T1 is now both proof (parser) and isolation (driver / C shim).

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
   The W9.1 boot counter bounds the *availability* damage of a persistently bad
   slot (N retries → slot lock → brick/recovery), but the counter itself is only
   as trusted as the image it ships with — same limitation, no HWRoT.
5. **x86_64 MCS is formally verified weaker than ARM MCS** (upstream status).
6. **Patched seL4.** The local patches modify a formally verified kernel; the
   upstream proof transfers only partially (§9).
7. **Watchdog/DoS.** A hardware watchdog (future work) recovers from hangs but
   is itself a DoS amplifier if an attacker can trigger hangs; it is a last
   resort *after* containment, not a substitute for it.
8. **PID reuse without delay (CVE-2026-SCHILD-02 #005).** Process IDs are
   recycled immediately on termination with no cool-down window, so a signal or
   IPC message intended for a just-terminated process can reach an unrelated
   successor that happens to reuse the same PID. Noted, not yet mitigated
   (bound the window with a monotonically increasing PID or a reuse delay).

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
- [`ROADMAP.md`](ROADMAP.md) — work order (W1–W10) and out-of-scope notes.
- [`DEVELOPMENT_VECTORS.md`](DEVELOPMENT_VECTORS.md) — reference codebases and DO-333 prep.
- [`security/CVE-2026-SCHILD-01.md`](security/CVE-2026-SCHILD-01.md), [`security/CVE-2026-SCHILD-02.md`](security/CVE-2026-SCHILD-02.md) — past audit findings (all fixed).




---

## 12. Corrections from audit v0.4 (2026-11-03) — supersedes conflicts in §3-§11

> **Status of this section.** Appended by external security audit (registry:
> `START/AUDIT_REGISTRY.md`). Corrections marked C-§N amend §N. Until §3-§11
> are inlined, this section is normative where it conflicts. This addendum
> makes THREAT_MODEL v1.1.0-audit.

### 12.1 Corrections to §3 (Adversary model)

**C-§3.1 P4 vs AS4.** P4 (local build/deploy access) and AS4 (boot chain
not attacker-controlled) are incompatible. AS4 applies to P1-P3 only. Against
P4, boot integrity and update integrity are **not claimed** (§8.4 already
acknowledges this, but §5 AS4 read alone was misleading).

### 12.2 Corrections to §4 (Trust boundaries)

**C-§4 TB3.** TB3 is enforced by architecture (with-clause discipline), not
mechanically. One with-clause linking a Tier B body into Tier A passes the
proof silently. This is a process control, not a mechanical check. Tier B
spec, on which Tier A depends, are part of the TCB and are listed in §9
(corrected, AS7). Mechanical guard is a build check (nm on Tier A binary,
fail on any Tier B symbol) — audit H4.

**C-§4 TB4 (Pi 4).** On Raspberry Pi 4 (bcm2711) there is no SMMU, and GENET
is an additional DMA master. P3 (malicious/compromised peripheral) is strictly
worse on Pi 4 than on x86_64. Pi 4 is not in current TCB scope; DMA analysis
for Pi 4 is a separate profile (§6 corrected).

### 12.3 Corrections to §5 (Assumptions)

**C-§5 AS4.** Scope clarified: applies to P1-P3, void against P4.

**AS6 — syscall seam (new).** `Schild_Sel4_Syscall` body is
`SPARK_Mode => Off` (1475 lines, audit C10), plus C shims
(`schild_sel4_ipc.c`, `schild_sel4_syscalls.S`, `message_info.c`). Trusted,
not proven. Maps Ada contracts to seL4 ABI. A bug here lets a domain escape
CSpace/VSpace. Per §3.2 (AI-axis), AS6 is **assumed exploitable**; under P2
the containment story fails unless AS6 holds.

**AS7 — spec Tier B (new).** Tier A depends on spec (contracts) of Tier B
services it calls. Those spec are trusted axioms, listed in §9 (corrected).
A compromised Tier B body (P2) may violate its own spec, in which case
Tier A's proof does not carry to the running system.

### 12.4 Corrections to §6 (Out of scope)

**C-§6 Pi 4.** Remove "Raspberry Pi 4 has no SMMU" as justification for
out-of-scope DMA. Replace with: "Pi 4 is not in current TCB scope. When Pi 4
enters scope, DMA isolation must be re-analyzed; absence of SMMU means P3 is
strictly worse than x86_64, not that DMA is out of scope."

### 12.5 Corrections to §7 (Threat → mechanism → check)

**C-§7 T1.** T1 module-level proven: `Parse_Tcp`/`Parse_Udp`/`Parse_Arp`/
`Parse_Ipv4`/`Validate_Tcp_Checksum` and `schild_http_core` are L4-proved.
Response builder (`Write_Str`, `Write_U32_Dec`) is proved (W11.3). Request
handler `Handle_Request` (`schild_http_server.adb`, Off) is **not** proved:
contains a runtime guard for request path (5..1024), but the response path
had an unguarded Pre violation (audit C23, patched 2026-11-03). T1 as written
is accurate for parsers, not for the handler.

**C-§7 T5.** MCS CPU budgets address CPU starvation but **not** IPC message
flood. A high-frequency P2 sender can starve the root task's IPC budget at low
CPU cost. Not covered by T5 as written (residual R15).

**C-§7 T8.** Split:
- **T8a** — Tier B C shims (`net_test.c`, `sel4_mmio.c` in Ring 3 domains):
  memory-unsafe, containment works (Ring 3 crash, core survives).
- **T8b** — ring-0 trusted C (`runtime_stubs.c`, `interrupt_handlers.c`,
  `hw_io.c`, `boot.S`): memory-unsafe, **containment does not work**. A bug
  here panics the kernel or gives Ring 0 execution. Trusted (§9), assumed
  exploitable under AI-axis. Larger residual than T8 originally written.

**T10 — DDE/GENET drivers (new).** When DDE-imported drivers or the GENET
driver enter the tree, they are Tier B (Ring 3, containment). Spec of the
driver service is trusted (AS7). Tier A must be independent of the driver
body — enforced by TB3 process control plus a build nm-check (audit H4).

**T11 — Watchdog DoS amplifier (new).** Watchdog is last-resort recovery,
not a substitute for containment. If P1 can trigger a NetServer hang that
trips the watchdog, P1 gets a reboot on demand. Requirement: watchdog trigger
gated by policy in root task, rate-limited, and must NOT fire for contained
faults (contained fault is handled by fault endpoint; watchdog is only for
unresponsive-but-not-faulted states).

**T12 — Health check through Tier B (new).** `Health_Status`
(Network_Up, MLS_Valid) is read from Tier B services. A compromised Tier B
returns fake "healthy"; `Commit_If_Healthy` commits; lockout never fires;
availability protection against a persistently bad slot is bypassed. Tier A
claim (boot reliability) dependent on Tier B truthfulness. Audit C9.

**T13 — Shared DMA frame cross-trust (new).** The 4 KB shared frame at
`0x520000` is mapped into both root task and NetServer. If root task reads
data written by NetServer (RX log path currently does) and NetServer is
compromised (P2), root task trusts fake data. Design rule: root task writes
for TX (safe), reads for RX-log only with explicit trust acknowledgment, or
moves RX log to structured IPC. Audit C8.

### 12.6 Corrections to §8 (Residual risks)

Additional residuals:

**R9 — Ring-0 C, no containment.** `runtime_stubs.c`,
`interrupt_handlers.c`, `hw_io.c`, `boot.S` are ring-0 trusted, memory-unsafe,
runtime-tested only. A bug here is not contained. Under AI-axis (assumed
exploitable), largest single residual after DMA.

**R10 — Syscall seam Off (1475 lines).** `Schild_Sel4_Syscall` body Off.
Bug here lets a domain escape CSpace/VSpace. Both Ada body and C shims are
trusted, not proven.

**R11 — Spec Tier B trusted.** See AS7. Tier A proof carries only if Tier B
spec are honored by Tier B bodies; under P2 they may not be.

**R12 — Boot counter / health through Tier B.** See T12, T13. Tier A claims
of boot reliability depend on Tier B truthfulness.

**R13 — Pi 4 DMA (when platform enters scope).** No SMMU. P3 strictly worse.
Separate analysis required before claiming Pi 4 as TCB platform.

**R14 — HTTP response path (audit C23, patched 2026-11-03).** Guard added
in `Handle_Request`. Verify on next regression: undersized `Reply_Buf`
returns `Success=False` without OOB.

**R15 — IPC flood (audit H2).** MCS budgets do not gate IPC frequency.
Liveness under P2 IPC flood is open.

### 12.7 Corrections to §9 (Trusted list)

Expand to include:

- **Upstream seL4** — as before.
- **Local patches** — `patches/seL4-smap.patch`,
  `seL4-object-zeroing.patch`, `seL4-framebuffer*.patch` (x3),
  `seL4-max-num-drhu.patch`, `seL4-bootinfo-8k-untyped.patch`.
  Each modifies verified kernel; reviewed but not re-proven. **AS8**: if any
  patch introduces a defect, the transferred guarantee is void.
- **Syscall seam** — `Schild_Sel4_Syscall` body (1475 lines Off), C shims.
  AS6 above.
- **Spec Tier B** — contracts of Tier B services called from Tier A. AS7 above.
- **Ring-0 trusted C** — `runtime_stubs.c`, `interrupt_handlers.c`,
  `hw_io.c`, `boot.S`. Runtime-tested only.

Each is trusted, not proven. §10's "if seam cannot be proven, record here" —
these are the records.

### 12.8 Corrections to §10 (Methodology)

**C-§10 anti-vacuity.** gnatprove's vacuity check catches **unreachable Pre**,
not **tautological Post**. `Post => True` (or equivalent) is not caught by the
tool; it is caught by human review. Historical example: W11.1 removed
`Post => (Is_Chain_Valid = constant True)` from `schild_audit_chainer` — that
vacuity passed all gates until manual review. §10 item 4 ("Post => True is
rejected") must state: rejected by human review, not by gnatprove.

### 12.9 Reference to audit registry

Ongoing findings tracked in `START/AUDIT_REGISTRY.md`. As of v0.4, findings
in C1, C3, C8, C9, C10, H1, H2, H3, H5, C22 are here recorded as acknowledged
residuals or assumptions, not as code bugs. They remain open in the registry
with status "documented in TM §12" until either (a) code mitigates or
(b) inline integration into §3-§11.


### 12.10 FS hardening + threat model refinement (audit v0.7, 2026-11-03)

**Source:** developer notes + audit cross-check. Half of these were already in §12; the rest are new.

**C-§3.2 AI-axis (concretize).** Split T1 into T1a (single malformed packet, parser memory safety — proven) and T1b (fuzzing-for-race, sequence of legitimate packets targeting connection state / parser state interactions). T1b is the AI-agent fuzzing scenario; not proven, contained by NetServer Ring 3 isolation.

**C-§7 T14 (PID reuse).** Moved from §8.8 residual into the threat table as T14. Threat: P2 sends signal or IPC to a PID that was just recycled by an unrelated process. Status: **deferred to v0.2.0** (design in progress: monotonic PID or reuse delay; capability-based identity preferred long-term). Tracked in audit registry as M1.

**C-§7 T15 (FS metadata tamper, HMAC key placement).** The FS metadata is protected by CRC32 (integrity, not authenticity). P3 (malicious NVMe via DMA) or P4 (write access to disk) can tamper and recompute CRC32. Moving to HMAC-SHA256 requires answering: where does the key live? (a) NetServer (Tier B) — P2 can read it; HMAC protects only against P3. (b) Root task (Tier A) — FS must migrate to Tier A or verify HMAC over IPC per block. (c) Hardware key store — not available (no TPM, no HWRoT). Until decided, FS metadata tamper remains accepted residual (R18). Audit H61.

**C-§8 R16 (signed boot without HWRoT).** P4 with write access to the disk can recompute SHA-256. Without TPM/HWRoT there is no defence. Accepted architectural risk. Boot counter lockout (W9.1) limits availability damage from bad slots, not integrity from malicious P4. This was already stated in §8.4; explicitly restated here as accepted.

**C-§8 R17 (path traversal — architectural mitigation).** `SchildFS.Open` searches by name in a flat `Root_Dir (0..15)` table; there is no hierarchy. `GET /../../etc/passwd` yields a name that matches nothing → 404. Architecturally closed, not mathematically proven. If the FS ever gains directory hierarchy, re-analyze. Audit H20 → CLOSED (architectural).

**C-§8 R18 (FS metadata tamper).** See T15. CRC32 detects corruption, not tampering. Accepted until HMAC key placement is decided.

**C-§9 (patches scope).** Clarify §9's local patches: they do NOT touch the capability model or the scheduler. They DO touch object lifecycle (`seL4-object-zeroing.patch`, security-relevant: uninit memory disclosure) and kernel memory layout (`seL4-bootinfo-8k-untyped.patch`). AS8 applies: if `object-zeroing` or `bootinfo-8k` introduces a defect, kernel memory disclosure is possible; containment depends on seL4's capability model remaining intact (which patches do not touch). Audit H10 remains open, but its scope is narrowed: patches affect object lifecycle and memory layout, not capability model or scheduler.

**C-§9 AS6 refinement.** `Schild_Sel4_Syscall` body is Off (1475 lines). The syscall seam is the largest single trusted component. Mitigations in queue (audit C4): memory-safe C shim, fuzzing of ABI mapping, formal ABI specification. Not fixed in v0.1.0.

