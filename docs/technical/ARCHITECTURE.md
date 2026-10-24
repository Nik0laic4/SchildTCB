# Schild TCB — Technical data sheet

**Version:** v1.0.0-pre (Stage 11)  |  **Date:** 2026-08-16
**Developer:** Ирганов А.Н.
**NetServer isolation:** CSpace ✅ (own CNode) · VSpace ✅ (own ASID-bound PML4) · IRQ ✅ · DMA frame ✅ · crash-containment ✅
**Build:** 177 objects + C + ASM → 0 errors
**Root Task ELF:** ~239 KB (with NetServer)  |  **kernel.elf:** ~186 KB (nehalem, PRINTING=ON)

---

## 1. PURPOSE AND SCOPE

Schild TCB is a high-assurance research prototype on the seL4 microkernel
with an Ada/SPARK user-space environment (MLS policy formally verified; drivers not).

**Target use cases:**
- Critical information infrastructure (CII)
- Energy and communications facilities
- Data centers with mandatory access control
- Research on formally verified computing environments

**Key characteristics:**
- seL4 microkernel (GPL-2.0-only) — 195 KB; upstream-proofed, locally patched
- Root Task in Ada/SPARK — 55 KB
- Bell-LaPadula MLS (Multi-Level Security)
- SPARK Level 4: MLS Bell-LaPadula policy proved (gnatprove 0 unproved)
- Hardware platform: x86_64, QEMU, built on Linux

---

## 2. ARCHITECTURE DIAGRAM

```
┌──────────────────────────────────────────────────────────┐
│  Ring 3 — User-space environment (internal)              │
│  ┌────────────────────────────────────────────────────┐  │
│  │ Root Task (schild_root_task.adb)                     │  │
│  │  ├─ Config Daemon      (SPARK Level 4)             │  │
│  │  ├─ A/B Boot Manager   (SPARK Level 4)             │  │
│  │  ├─ MLS Policy Daemon  (SPARK Level 4)             │  │
│  │  ├─ Audit Logger       (SPARK Level 4)             │  │
│  │  ├─ Launch_MLS_Server  (12-step pipeline)          │  │
│  │  └─ Fault Handler      (blocking Recv — containment) │  │
│  ├────────────────────────────────────────────────────┤  │
│  │ MLS Server Thread (mls_server.c)                   │  │
│  │  └─ Bell-LaPadula IPC filter                        │  │
│  ├────────────────────────────────────────────────────┤  │
│  │ NetServer Thread (netserver.c + Ada, net_ep)        │  │
│  │  └─ e1000e + TCP/IP (MMIO @ 0x600000, DMA physics)  │  │
│  ├────────────────────────────────────────────────────┤  │
│  │ Schild TCB Kernel (176 Ada modules, bare-metal)     │  │
│  │  ├─ 01_hardware: HAL, MMU, APIC, NVMe, e1000e      │  │
│  │  ├─ 02_security:  MLS Core, IPC Gateway, Firewall   │  │
│  │  ├─ 03_crypto:   AES-NI, TME, SHA-256, RNG          │  │
│  │  └─ 04_userland: VFS, Sockets, Net Stack, ARP/UDP   │  │
│  └────────────────────────────────────────────────────┘  │
├──────────────────────────────────────────────────────────┤
│              syscall ABI (ABI boundary)                   │
│   SysCall=-1 ReplyRecv=-2 Send=-5 Recv=-7 Wait=-9         │
├──────────────────────────────────────────────────────────┤
│  Ring 0 — seL4 microkernel (GPL-2.0-only)                 │
│  └─ kernel.elf: x86_64, nehalem, PCID=OFF, PRINTING=ON    │
└──────────────────────────────────────────────────────────┘
```

**Architectural boundary:** the Root Task and the seL4 kernel are separate
Multiboot2 binary modules. They interact exclusively through the standard
syscall ABI. They are not derivative works of one another.

---

## 3. TECHNICAL SPECIFICATIONS

### 3.1. Build pipeline

| Component | Tool | Version |
|-----------|-----------|--------|
| Ada/SPARK | GNAT (Alire) | 14.2.1 |
| C | GCC | 14.2.0 |
| Assembler | GNU AS | 2.42 |
| Linker | GNU LD | 2.42 |
| Verification | Alt-Ergo / Why3 | 2.4.0 / 1.6.0 |
| ISO image | grub-mkrescue | 2.12 |

**Build (single command):**
```bash
cd src/schild_core
SEL4_PRIMARY=1 ./build.sh
# → 176 Ada + 0 errors, root_task.elf ~55 KB, sel4_primary.iso
```

**Run:**
```bash
timeout 10 qemu-system-x86_64 -cdrom sel4_primary.iso \
  -nographic -m 512M -smp 1 -no-reboot -cpu max
```

### 3.2. Component sizes

| Component | Size |
|-----------|--------|
| root_task.elf (Ada/SPARK) | ~55 000 bytes |
| kernel.elf (seL4, C/ASM) | ~195 000 bytes |
| sel4_primary.iso | ~22 MB |

### 3.3. Source file stack

| Language | Files | Purpose |
|------|--------|------------|
| Ada (.ads/.adb) | 176 | Kernel, drivers, SPARK modules |
| C (.c) | 6 | seL4 IPC, runtime stubs, interrupts |
| ASM (.S) | 3 | Entry point, syscall stubs, MLS server |

---

## 4. SECURITY SUBSYSTEMS

### 4.1. MLS Bell-LaPadula (SPARK Level 4)

Verified mandatory access control model (gnatprove, 0 unproved):

| Rule | Contract (SPARK) | Status |
|---------|-----------------|--------|
| No Read Up | `Subject >= Object` | ✅ Proved |
| No Write Down | `Subject <= Object` | ✅ Proved |
| Strict IPC | `Sender = Receiver` | ✅ Proved |

**Levels:** Public → Internal → Confidential → Secret → Top_Secret

### 4.2. Audit (SPARK Level 4)

- Ring buffer (64 events)
- Severity filter (RFC 5424 syslog)
- Overflow protection (FIFO dropping the oldest)
- Contract: `Event_Count'Post = Event_Count'Old + 1`

### 4.3. Configuration daemon (SPARK Level 4)

- Junos pattern: validate → commit confirmed <timeout>
- Auto-rollback on timeout
- 4 configuration domains: Security, Network, Boot, Audit

### 4.4. A/B Boot Manager (SPARK Level 4)

- Two boot slots (A/B)
- SHA-256 image verification
- Atomic failover
- Contract: `Failover: Active_Slot /= Active_Slot'Old`

---

## 5. NETWORK SUBSYSTEM

### 5.1. Drivers (Ada)

| Driver | Language | Status |
|---------|------|--------|
| Intel e1000e | Ada | ✅ |
| VirtIO-net | Ada | ✅ |

### 5.2. Network stack (Ada/SPARK)

| Module | SPARK | Purpose |
|--------|-------|------------|
| ARP Guard | On | ARP table, spoofing protection |
| UDP Handler | Off | UDP handler |
| Net Parser | — | IPv4 frame parsing |
| Net Filter | — | Packet filtering |
| Firewall | — | Firewall |
| Socket Manager | On | Socket isolation |

---

## 6. seL4 INTEGRATION

### 6.1. Syscall ABI (MCS)

| Syscall | Number | Purpose |
|---------|-------|------------|
| SysCall | -1 | Generic (invocations + IPC Call) |
| SysReplyRecv | -2 | Reply then receive (MCS) |
| SysSend | -5 | IPC send (fire-and-forget) |
| SysRecv | -7 | IPC receive with reply object (blocking) |
| SysNBRecv | -8 | IPC receive with reply object (non-blocking) |
| SysWait | -9 | IPC receive, no reply object (blocking) |
| SysNBWait | -10 | IPC receive, no reply object (non-blocking) |
| SysYield | -11 | Yield the current timeslice |
| SysDebugPutChar | -12 | Debug output to UART |

### 6.2. Invocation labels (MCS)

| Label | Method | Purpose |
|-------|-------|------------|
| 1 | UntypedRetype | Create objects from untyped |
| 3 | TCBWriteRegisters | Write RIP/RSP into TCB |
| 9 | TCBSetTimeoutEndpoint | Timeout fault endpoint (MCS) |
| 10 | TCBSetIPCBuffer | Configure the IPC buffer |
| 11 | TCBSetSpace | CSpace/VSpace/Fault EP |
| 13 | TCBResume | Start a thread |
| 22 | CNodeMint | Copy a capability (badge/rights) |
| 33 | SchedControlConfigureFlags | Set SC budget/period |
| 34 | SchedContextBind | Bind TCB to a scheduling context |
| 45 | X86PageMap | Map a 4K frame |

### 6.3. Cap slot map

| Slot | Purpose |
|------|------------|
| 1 | TCB (root task) |
| 2 | CNode (12 bits = 4096 slots) |
| 3 | VSpace (Page Directory) |
| 10 | IPC Buffer Frame (seL4_CapInitThreadIPCBuffer) |
| 100 | Fault Endpoint (root task) |
| 199 | Fault Notification (MLS TCB) |
| 200 | MLS TCB |
| 501 | MLS Endpoint |

---

## 7. BOOT PROCEDURE

```
1. GRUB2 → Multiboot2
2. seL4 kernel.elf (Ring 0): CPU init, MMU, cap caching
3. root_task.elf (Ring 3):
   a. Read BootInfo (memory map, untyped)
   b. SPARK tests: Config Daemon (T1-T4)
   c. SPARK tests: MLS Policy (T5-T7)
   d. SPARK tests: Audit Logger (T8)
   e. Init_Fault_Handler: Retype Endpoint, TCBSetSpace
   f. Launch_MLS_Server: 10-step pipeline
   g. blocking Recv on the fault endpoint (containment) + NBRecv for e1000e IRQ
```

### Output to UART (successful boot)

```
==== Schild TCB Root Task (Ada/SPARK 2022) ====
Node: 0 / 1
CSpace: 2^12 slots
Untyped: 50 caps
----- Memory Map -----
  #0: 0x00000000 .. 0x0009FC00  [RAM]
  #1: 0x00100000 .. 0x1FFE0000  [RAM] (510 MB)
  ...
----- Summary -----
Total RAM: 510 MB
[S7] T1 PASS ... [S7] T4 PASS
[S7.2] T5 PASS ... [S7.2] T8 PASS
----- Stage 6: Fault Handler -----
[Stage6] Fault handler ready.
----- Stage 7.7: Launching MLS Server -----
[S7.7] MLS Server: OK
==== Root Task ready ====
```

---

## 8. VERIFIED INVARIANTS (SPARK)

| # | Module | Contract | Status |
|---|--------|----------|--------|
| 1 | MMU Overseer | `(Addr and 0xFFF) = 0` | ✅ |
| 2 | Frame Allocator | `PhysAddr < Kernel_Limit` | ✅ |
| 3 | Timer | `Ticks = Ticks'Old + 1` | ✅ |
| 4 | Syscall Fabric | `Context.Args_Valid` | ✅ |
| 5 | MLS Core | `Sub_Level >= Obj_Level` | ✅ |
| 6 | MLS Assigner | `Final_Level >= Current` | ✅ |
| 7 | Module Verifier | `Computed_Hash = Expected` | ✅ |
| 8 | ICMP Handler | `Raw_Len in 8..65507` | ✅ |
| 9 | Mount Manager | `Point.Ctx_Id = Target` | ✅ |

**MLS Bell-LaPadula policy: 0 unproved (gnatprove). Root-task orchestration (W4): `schild_root_task.adb` `SPARK_Mode => On` (54 checks); `Schild_Launch_Model` / `Schild_HM_Model` (Level 4). Storage isolation (W7): NVMe + SchildFS run in the Ring 3 NetServer (`[NVFS] Read-back VERIFY OK`, QEMU 20/20). HW/driver/crypto: `SPARK_Mode => Off`.**

---

## 9. LICENSING

Собственный код (ядро, root-задача, драйверы) распространяется под лицензией
GPL-2.0-only. Третьесторонние компоненты — под своими лицензиями
(seL4 — GPL-2.0-only; GNAT runtime — GMGPL).
Полный перечень — в [`NOTICE.md`](../../NOTICE.md).

---

## 10. VERSION HISTORY

| Version | Date | Key changes |
|--------|------|-------------------|
| v1.0.0-pre S12 | 2026-10-04 | W4: root-task `SPARK_Mode => On` (54 checks, 7 daemons); `Schild_Launch_Model`; syscall seam contracted; W5: Fastpath non-MCS-specific; W7: NVMe+SchildFS isolated in NetServer |
| v1.0.0-pre S11 | 2026-08-16 | ECAM PCI, UEFI boot fix, T580 bring-up (NVMe + e1000e + SMP + HTTP) |
| v0.9.0-pre S7.7 | 2026-08-12 | IPC buffer (slot 10), Call infrastructure, PageMap, Ирганов А.Н. |
| v0.9.0-pre S7.6 | 2026-08-11 | SPARK Audit 12/12, MLS Thread, TCBWriteRegisters |
| v0.9.0-pre S7.5 | 2026-08-10 | BootInfo fix, RAM untyped filter, device bypass |
| v0.5.0-pre | 2025-2026 | Multiboot2, Long Mode, UART, NVMe, SMP |

---

## 11. KNOWN LIMITATIONS (Stage 8.0)

### Resolved (Stage 8.0)
1. **KERNEL #GP on TCBSetSpace** → FIXED: `memzero` TCB on creation
2. **Phantom syscall errors (0x1E/0x5E/0x5F/0xC8)** → FIXED: `raw_send` reads RSI
3. **One untyped for 3 objects** → FIXED: UT1/UT2/UT3
4. **RAM untyped dropped from BootInfo** → FIXED: limit 50→128
5. **"unknown syscall 0x406ee8"** → FIXED: `send_ipc` loaded SysSend into RBX (immediate)
6. **MLS thread starts with RIP=0** → FIXED: `TCBWriteRegisters` count=3 + rip/rsp/rflags order
7. **NULL-deref in sendIPC** → FIXED: `memzero` endpoint/notification in createObject
8. **`Slot #100 non-empty` (NBRecv fault)** → FIXED: fault-handler slot 100→500
9. **`reply`/`recv` ABI** → FIXED: info RDI→RSI, RSI zeroing, `"=S"` return
10. **End-to-end IPC** → ✅ Root Task → Call → MLS → Recv → Reply → Root Task (0 faults)

### Remaining (Stage 11)
1. **e1000e IRQ-driven RX (seL4 NetServer path)**: ✅ RESOLVED (W2). The root
   task discovers the real I219-V via ECAM, programs MSI, and maps BAR0
   (`0xE8200000`) into the NetServer VSpace. Validated on the T580 — IRQ-driven
   RX (Notification badge `0xE1`) + end-to-end TCP/HTTP served from the
   isolated Ring 3 NetServer.
2. **IOMMU (P0-3)**: device isolation after device-bypass removal (PCI-scan +
   MSI-detect on real hardware — TODO P1).
3. **seL4 MCS**: ✅ QEMU-валидирован (temporal isolation: CPU budgets, timeouts —
   `Setup_MCS_Thread`, sporadic Config Daemon, `seL4_Fault_Timeout` via shared
   timeout endpoint). Формально верифицирован слабее ARM MCS (отражено в
   assurance-кейсе).

## 12. CONTACT

**Developer:** Ирганов А.Н.  
**License:** см. [`NOTICE.md`](../../NOTICE.md)
