![Schild TCB](../assets/brand/wordmark_color.png){width=9cm}

# Schild TCB: A Reference Architecture for Formally Verified Services on seL4

**Alexander Irganov** · Independent researcher, Russia

**v1.0 — 2026-11-23** (replaces the 2026-11-01 draft, commit `fd97c120`)

> Updated from the first draft. The SPARK numbers are generated from
> `obj/proof/metrics.json` (see the block in Results); a companion community
> textbook (15 case studies, RU+EN) and the Zenodo archive are cited.
>
> Concept DOI (all versions): [10.5281/zenodo.24446686](https://doi.org/10.5281/zenodo.24446686) ·
> This release (v1.0.0-textbook): [10.5281/zenodo.24446687](https://doi.org/10.5281/zenodo.24446687)

## Abstract

Schild TCB is a research prototype of a Trusted Computing Base that pairs the
seL4 microkernel [Klein2009] with an Ada/SPARK 2022 user-space environment. The
kernel itself is formally verified upstream; this prototype applies eight small
local patches (see SEL4_PATCHES_ANALYSIS.md) that are NOT covered by that proof:
seven lie in the boot / cache-maintenance code that the upstream proof
explicitly excludes, and one (object zeroing) modifies createObject() inside the
refinement-proof region. The l4v proof suite has not been re-run on the patched
tree; "formally verified seL4" therefore means "seL4 plus a small,
self-reviewed, unproven delta".

The security-critical core — an MLS Bell-LaPadula policy, a capability model, a
process table, and firewall verdicts — is proved at SPARK Level 4 with zero
unproved verification conditions (**133 of 179 modules in proof, 0 unproved
VCs**; see the metrics block in Results). Untrusted periphery (network driver
and storage) runs isolated in Ring 3, so a process-level fault or compromise
there cannot reach the proved core; a malicious DMA-capable device remains a
residual risk (see Limitations).

The system boots on a ThinkPad T580 (32 GB) and in QEMU, with an ARM64
(Raspberry Pi 4B) port in progress. A companion community textbook (15 case
studies, RU+EN) untangles the engineering changelog through the code. This
paper describes the architecture, the threat model, and the contract-driven
verification approach, and states the honest limits of the current prototype
(no DMA isolation, weaker x86_64 MCS verification).

## Introduction

Modern systems concentrate privilege in a single monolithic kernel: one memory
bug in any driver — network, storage, USB — yields full compromise. Formal
verification of such a kernel is intractable, so the industry patches
reactively. The alternative, followed here, is to make the *trusted* part small
enough to verify and to *isolate* everything else.

A second pressure is capability, not surface: autonomous AI agents lower the
cost of chaining many bugs into one exploit to near zero — a dynamic made
concrete by AI-assisted discoveries such as the Linux kernel use-after-free
[CVE202698432] found by Claude [Anthropic2026Claude]. Against such an
adversary the only controls that do not degrade are machine-checkable proof and
kernel-enforced isolation (THREAT_MODEL §3.2). Schild TCB is an experiment in
building exactly that: a proved core plus contained periphery.

The code and proofs are open: <https://github.com/Nik0laic4/SchildTCB>.
A companion "community textbook" — fifteen case studies that untangle the
engineering changelog through the code, from a vacuous contract to the dead
gate — is published alongside the repository (RU+EN) and archived on Zenodo
(concept DOI 10.5281/zenodo.24446686; version 10.5281/zenodo.24446687).

## Architecture

Two artifacts, separated by the syscall ABI:

- **seL4 microkernel** (Ring 0) — upstream, locally patched (SMAP, object
  zeroing, the framebuffer trio, bootinfo-8k, max-num-drhu, load-image); see
  Limitations for the proof status.
- **Root task** (Ring 3) — Ada/SPARK 2022. Orchestrates the daemons and the
  two-level ARINC-653 schedule [ARINC653, Rushby1999]; NetServer is a separate
  isolated ELF.

*(The block diagram is Figure 1.)*

Isolation is three-fold: **CSpace** (own CNode), **VSpace** (own ASID-bound page
table), and **IRQ/DMA** (dedicated notifications + DMA frame). A fault in
NetServer is caught by the fault handler and contained without rebooting. Each
daemon runs as a separately loaded ELF with its own CSpace and VSpace, so a
compromise of one daemon cannot mint capabilities into another's slot map.

MLS is enforced in a userspace server rather than via seL4's static infoflow
configuration because the policy is dynamic and data-dependent (per-file levels,
operation-aware `Authorize_File_Op`): the upstream infoflow theorems hold for a
fixed configuration and do not express per-file, per-operation policy. The MLS
server is in the TCB, and its isolation rests on the patched kernel.

Trust is split by tier (ASSURANCE.md): **Tier A** (proved core: MLS, capability
model, process table, firewall verdicts), **Tier B** (contained periphery:
network/storage), **Tier C** (explicitly-labelled scaffold). The rule that Tier A
depends on Tier-B *specifications*, never Tier-B *bodies*, is enforced by review
and by the `forbidden_check` pre-commit gate (which rejects `SPARK_Mode => Off`
in Tier-A modules); a full dependency checker is future work.

## Threat Model

Assets (A1–A6): the proved core, the isolated periphery, the TCB runtime, the
audit log, the boot/update path, and the platform. Four adversary classes:

- **P1 — remote network attacker** (reaches only the TCP/IP/HTTP surface);
- **P2 — compromised Tier-B domain** (already inside an isolated driver);
- **P3 — malicious/compromised peripheral** (DMA-capable device);
- **P4 — local build/deploy access** (can replace images).

On top of P1–P4, the **AI-agent cascade** is a capability axis, not a fifth
class: it multiplies existing classes by lowering cost and by chaining bugs
(THREAT_MODEL §3.2). Every unproven line is assumed already exploitable.

## Implementation & Verification

The proved core is written in SPARK [AdaCoreSPARK], with every security property
re-expressed as a contract and discharged by `gnatprove --level=4 --mode=all`
(CVC5/Z3/Alt-Ergo); level 4 is the prover effort (strategies, timeouts), not a
guarantee level. The method (THREAT_MODEL §10): `Pre` accepts **all** legitimate
inputs, `Post` states the **security property**, liveness is validated by
runtime/KAT tests rather than proof, vacuity is rejected, and `pragma Assume`
stays at zero.

Representative proved properties: CBC chaining (`schild_aes_cbc_engine`),
maximum-priority scheduling + ARINC-653 MTF (`schild_scheduler`, `schild_mtf`),
Bell-LaPadula no-read-up/no-write-down (`schild_server_security_policy`,
`schild_file_descriptors`), and memory-safe network parsers
(`schild_arp/ipv4/icmp/udp/tcp_handler`). The CBC engine wraps a portable
software AES-128 whose S-box and 10-round transform sit outside the proof gate
(the body is `SPARK_Mode => Off`); only the no-out-of-bounds chaining around it
is proved, and FIPS 800-38A conformance is established by KAT, not proof.
`schild_sha256_compress` was extracted from the FS daemon (a module split) and
validated by RFC 4231 / NIST KAT. The MLS storage layer gained per-file levels
and an operation-aware gate (`Authorize_File_Op`) covering all seven filesystem
operations. Parser `Pre` conditions are caller obligations, so each parser body
carries an explicit runtime guard (reject `Raw'Length < 20` for IPv4/TCP,
`< 28` for ARP) before any field access, a defensive check for Off-mode callers.
Techniques and gotchas are collected in `SPARK_PROOF_TECHNIQUES.md`; a
build→run→verify tutorial is `GUIDE.md`.

The scheduling policy is proved at the SPARK level (`Find_Next_Task_In_Partition`,
the ARINC-653 MTF composition) and validated by KAT; the running system is
scheduled by seL4/MCS. The translation — priorities set at TCB creation and MTF
windows mapped to scheduling-context budgets — is an engineering argument,
checked jointly by the two-level KAT on identical inputs, not a theorem.

The quantitative claim is a **single machine-generated taxonomy**, not a hand-
edited figure: a deterministic classifier (`classify_gnatprove.py`) sorts every
module into `PROVED` / `SKIPPED` (body `SPARK_Mode => Off`) / `NO-OUTPUT` /
`NOT-PROVED` / `scaffold`, and `prove_kernel.sh` writes the result to
`obj/proof/metrics.json`; the numbers below are regenerated into every public
artifact with an explicit commit marker, so the README, the textbook, and this
paper cannot drift apart.

## Results

<!-- METRICS:START (generated by scripts/generate_metrics.py — do not edit) -->
**SPARK metrics** (commit `7700c54`, 2026-11-23): **189 swept** · **179 in proof** (133 proved · 44 skipped · 2 no-output) · **10 scaffold excluded** · **0 unproved VCs**.

Accounting: `swept` = all modules; `in_proof` = `swept` − `scaffold_excluded`; `proved + skipped + no_output + not_proved` = `in_proof`. Source: `obj/proof/metrics.json`.
<!-- METRICS:END -->

- 8 root-task proof units (1 daemon + 7 libraries/models) proved (`verify.sh`); full private bodies (`verify_private.sh`).
- Build: **184 objects, 0 errors**; boots on a **ThinkPad T580 (32 GB)** and QEMU.

The fault-containment and temporal-isolation markers are shown in the listing
below (Figure 2).

## Limitations & Future Work

- **Locally patched seL4** — eight local patches (SMAP, object zeroing, the framebuffer trio, bootinfo-8k, max-num-drhu, load-image) are self-reviewed, not re-proven. Only object-zeroing modifies `createObject()` inside the refinement-proof region; the other seven lie in upstream's documented unverified scope (boot code, cache maintenance). The l4v proof suite has NOT been re-run on the patched tree. See `SEL4_PATCHES_ANALYSIS.md`.
- **Ring-0 C code** — `runtime_stubs.c`, `interrupt_handlers.c`, `hw_io.c`, `boot.S` are trusted, not contained: memory-unsafe, and containment does not apply (THREAT_MODEL §12.5).
- **No DMA isolation** — IOMMU/VT-d is upstream-experimental; the Pi 4 has no SMMU. Isolation is process-level, not bus-level (P3 remains a residual risk).
- **IPC availability under P2** — MCS CPU budgets address CPU starvation but not IPC message flood: a high-frequency P2 sender can starve the root task's IPC budget at low CPU cost (THREAT_MODEL R15). Liveness under an IPC flood is open.
- **x86_64 MCS** is formally verified weaker than ARM MCS (upstream; the l4v README notes ARM has the most complete proof set, with MCS proofs on the `rt` branch).
- **Unproven C code** (C shims, drivers) — memory-unsafe, backed only by containment.
- **Local build/deploy (P4)** — partially covered: a boot counter bounds the damage of a malicious rollback, and SHA-256 detects corruption. Full supply-chain integrity is out of scope (no HWRoT/TPM).
- **Identity management** — PID reuse was mitigated via monotonic generation (v0.36), but true capability-based process identity remains a long-term architectural goal.

Next: the ARM64/GENET port when hardware is available, and per-property contract
strengthening toward the full end-to-end security property. A pilot use case
("protected network gateway with MLS") is already described in `USE_CASE.md`.

## Conclusion

Schild TCB demonstrates a pragmatic path between "verify the whole OS"
(intractable) and "patch reactively" (not credible against AI-speed
adversaries): keep the trusted core small and *proved*, and make everything else
*contained*. The result is a per-component, mechanically checkable assurance
story rather than a broad "high-assurance" label — with the remaining gaps (DMA
isolation, signed boot) stated honestly rather than hidden.

## References

> The in-text keys map 1:1 to the entries below; the repository link is stated
> in the Introduction.

**[Klein2009]** G. Klein et al. "seL4: Formal Verification of an OS Kernel." SOSP '09, ACM, 2009. doi:10.1145/1629575.1629596.

**[AdaCoreSPARK]** AdaCore. "SPARK 2014 User's Guide." 2024. <https://docs.adacore.com/spark2014-docs/html/ug/>.

**[CVE202698432]** "CVE-2026-98432: Linux kernel use-after-free via race in IPv4 TCP SYN/SYN-ACK handling." NVD, 2026. <https://nvd.nist.gov/vuln/detail/CVE-2026-98432>.

**[Anthropic2026Claude]** Anthropic. "Discovering and exploiting vulnerabilities in critical, real-world software with Claude." 2026. <https://www.anthropic.com/research/discovering-vulnerabilities-with-claude>.

**[ARINC653]** ARINC Specification 653: Avionics Application Software Standard Interface. Aeronautical Radio, Inc., 2003.

**[Rushby1999]** J. Rushby. "Partitioning in Avionics Architectures." SRI International, 1999. NASA CR-1999-209347.

**[SchildTextbook]** A. Irganov. "Schild TCB: A Field Guide to Walking a Minefield." 2026. doi:10.5281/zenodo.24446687 (concept 10.5281/zenodo.24446686).

**[SchildTCB]** A. Irganov. "Schild TCB — a TCB research prototype on seL4 (Ada/SPARK)." 2026. doi:10.5281/zenodo.24446687.

**[OpenSSF]** OpenSSF Best Practices Badge — Schild TCB. <https://www.bestpractices.dev/projects/16898>.

## Figures & Tables

### Figure 1 — Architecture (block diagram)

\begin{figure}[ht]
\centering
\begin{tikzpicture}[
    font=\small,
    box/.style={draw, rounded corners, align=center, inner sep=6pt, minimum width=4.0cm}
]
\node [box] (rt) at (0,2.4) {Root Task\\(Ada/SPARK 2022)};
\node [box] (d) at (-4.4,0.5) {Daemons\\Config · Boot\\MLS Policy · Audit};
\node [box] (ms) at (0,0.5) {MLS Server\\(Bell-LaPadula\\IPC filter)};
\node [box, draw=red] (ns) at (4.4,0.5) {NetServer\\e1000e + TCP/IP\\isolated · contained};
\node [box, fill=blue!8] (k0) at (0,-1.3) {seL4 microkernel\\(Ring 0, GPL-2.0-only)};
\draw [->] (rt) -- (d);
\draw [->] (rt) -- (ms);
\draw [->] (rt) -- (ns);
\draw [->] (d) -- (k0);
\draw [->] (ms) -- (k0);
\draw [->] (ns) -- (k0);
\node at (0,-0.35) [font=\small\bfseries] {syscall ABI};
\end{tikzpicture}
\caption{Architecture: Ring 3 (Root Task + four daemons, MLS Server, NetServer) over the syscall ABI to the Ring 0 seL4 microkernel. NetServer is isolated and contained.}
\label{fig:arch}
\end{figure}

*(Draw.io/Excalidraw spec for the diagram: two horizontal bands — top «Ring 3 (user space)», bottom «Ring 0». Top band: one «Root Task» box with three children (a group of 4 daemons, the MLS Server, the NetServer) connected by arrows. NetServer tinted red («isolated · contained»); a dashed line labelled «syscall ABI» separates the bands; seL4 box tinted blue.)*

### Table 1 — Verification results

\begin{table}[ht]
\centering
\footnotesize
\caption{Representative proved properties and the mechanical check that discharges them.}
\label{tab:verification}
\begin{tabular}{@{}lp{6.6cm}ll@{}}
\toprule
\textbf{Module} & \textbf{Proved property} & \textbf{Verification} & \textbf{Status} \\
\midrule
schild\_server\_security\_policy & Bell-LaPadula: no read-up / no write-down / strict IPC & prove\_kernel.sh & Proved \\
schild\_scheduler + schild\_mtf & maximum-priority ready task; ARINC-653 totality & prove\_kernel.sh & Proved \\
schild\_aes\_cbc\_engine & CBC chaining (FIPS 800-38A conformance by KAT) & prove\_kernel.sh & Proved \\
schild\_file\_descriptors & Bell-LaPadula soundness (no false access grant) & prove\_kernel.sh & Proved \\
schild\_cap\_space / process\_manager & capability + MLS invariants & prove\_kernel.sh & Proved \\
schild\_arp/ipv4/icmp/udp/tcp\_handler & memory-safe parsers (buffer-bound Pre) & prove\_kernel.sh & Proved \\
8 root-task proof units & daemon + library/model logic & verify.sh & Proved \\
e1000e / NVMe / network stack & drivers — not proven (no hardware spec) & run\_tests.sh & Contained \\
\midrule
\textbf{canonical metrics (see the Results block)} & \textbf{0 unproved VCs} & prove\_kernel.sh & \textbf{Pass} \\
\bottomrule
\end{tabular}
\end{table}

### Figure 2 — Containment markers

\begin{lstlisting}[language=bash, caption={Runtime validation of fault containment and temporal isolation on QEMU.}, label={lst:containment}]
PASS  [CONTAINMENT] injecting fault into NetServer
PASS  [FAULT] Caught fault
PASS  [CONTAINMENT] core alive after fault
PASS  [FAULT] Caught MLS fault
PASS  [CONTAINMENT] MLS server contained
PASS  [TIMEOUT] Caught budget overrun
PASS  ==== Root Task ready ====
\end{lstlisting}
