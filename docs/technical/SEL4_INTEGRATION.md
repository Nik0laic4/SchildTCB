# seL4 Integration — current state (2026-08-17)

> This file is a historical Stage-5/6/7/8 log. **Current state** (supersedes the
> old entries below):

- **Root task is on seL4 MCS** (migration complete, QEMU-validated — see
  `MCS_MIGRATION.md`). Per-thread scheduling contexts + reply objects,
  `ReplyRecv`/`Wait`/`NBWait` syscalls, per-partition budgets (B.5) and timeout
  endpoints (B.6).
- **Fault handler is an ENDPOINT** set via `TCBSetSpace` (MCS, label 11). Fault
  endpoints: root/NetServer=500 (NetServer badged 0xE2, minted into root CSpace
  214), MLS=199, Config=526. Crash-containment (`op=99`, reply then fault on
  unmapped `0xFFFFF000`) is demonstrated for **all three** domains, with the
  root task catching the fault via **blocking `Wait`** and restarting via
  `Health_Monitor`. Markers enforced by `run_tests.sh` (18 markers).
- **`sel4_primary.iso` boots on the T580** (32 GB) as of 2026-10-04 (framebuffer
  console); the seL4 NetServer drives the real I219-V via ECAM+MSI (W2). See
  `CHANGELOG.md` / `ROADMAP.md` for the canonical current state.

---


# Stage 8.0 — seL4 IPC Chain WORKING (syscall returns 0)

**Status:** UNTYPEDRETYPE → TCB → SETSPACE → WRITEREGS → RESUME — all return 0 ✅ (2026-08-12)

## Verified Syscall Chain (Stage 8.0)

```
[Stage6] TCBSetSpace -> raw=0x0000000000000000    SUCCESS
[S7.7] Endpoint at 501 -> 0x0                       SUCCESS
[S7.7] FaultNtfn at 199 -> 0x0                      SUCCESS
[S7.7] TCB at 200 -> 0x0                            SUCCESS
[S7.7] SetSpace -> 0x0                              SUCCESS
[S7.7] WriteRegs -> 0x0                             SUCCESS
[S7.7] Resume -> 0x0                                SUCCESS
[S7.7] IPC Send -> "Caught cap fault" (Recv stub bug, see below)
```

## 4 Root Causes Fixed (Stage 8.0)

| # | Root Cause | Fix |
|---|-----------|-----|
| 1 | TCB not zeroed → #GP (garbage CTE slots) | `memzero(regionBase, BIT(seL4_TCBBits))` in objecttype.c |
| 2 | raw_send reads RAX not RSI (phantom errors) | `"=a"` → `"=S"` in schild_sel4_ipc.c |
| 3 | Single untyped for 3 objects | UT1/UT2/UT3 |
| 4 | untyped caps 50 too small (RAM dropped) | 50→128 |

## Resolved (2026-08-12): IPC end-to-end WORKS

The "unknown syscall 0x406ee8" was NOT the Recv stub — it was `send_ipc` loading
the SysSend number into RBX (register operand clobbered by the RBX=RSP dance).
Additional fixes: `TCBWriteRegisters` count=3 + register order, `memzero` for
endpoint/notification in the kernel, fault-handler slot 100→500.

Final verified log:
```
[S7.7] Endpoint/FaultNtfn/TCB/SetSpace/WriteRegs/Resume... 0  (SUCCESS)
[S7.7] IPC Call... 1
[S7.7] Reply MR0 (result): 0     (Bell-LaPadula deny)
==== Root Task ready ====          (0 faults)
```

---

# Stage 7.7 — MLS IPC Pipeline: End-to-End Ready

**Status:** IPC BUFFER FIXED ✅ (2026-08-12)

## Architecture — MLS Thread Creation (Complete)

```
Root Task (Ring 3)
  │
  ├── Stage 7.1-7.2: Config + Boot + MLS Policy + Audit (8/8 PASS ✅)
  │
  ├── Stage 7.7: Launch_MLS_Server (12-step pipeline ✅)
  │     ├── Retype_Object(Endpoint)  → slot 501   ✅
  │     ├── Retype_Object(FaultNtfn) → slot 199   ✅
  │     ├── Retype_Object(Frame)     → slot 202   ✅
  │     ├── Retype_Object(TCB)       → slot 200   ✅
  │     ├── PageMap                  → 0x500000   ✅  (NEW!)
  │     ├── TCBSetIPCBuffer          → buf=202    ✅  (NEW! Critical fix)
  │     ├── TCBSetSpace              → fault=199  ✅
  │     ├── TCBWriteRegisters        → RIP+RSP   ✅
  │     ├── TCBResume                → start MLS  ✅
  │     └── Send_IPC                 → test msg   ✅
  │
  └── Stage 6: Fault handler + NBRecv (✅)
```

## seL4 Invocation Labels (Stage 7.7 verified)

| Label | Method | Extra Caps | Notes |
|-------|--------|------------|-------|
| 1 | UntypedRetype | 1 (root CNode) | Generic via Retype_Object |
| 3 | TCBWriteRegisters | 0 | Set RIP/RSP |
| **9** | **TCBSetIPCBuffer** | **1 (buffer frame)** | **NEW: MLS TCB IPC buf** |
| 10 | TCBSetSpace | 2 (cspace,vspace) | Fault handler binding |
| 12 | TCBResume | 0 | Start thread |
| **39** | **X86PageMap** | **1 (VSpace)** | **NEW: Map frame at 0x500000** |

## Object Types (x86_64 with CONFIG_HUGE_PAGE=1)

| Type | Constant | Value |
|------|----------|-------|
| UntypedObject | seL4_UntypedObject | 0 |
| TCBObject | seL4_TCBObject | 1 |
| EndpointObject | seL4_EndpointObject | 2 |
| NotificationObject | seL4_NotificationObject | 3 |
| CapTableObject | seL4_CapTableObject | 4 |
| 4K Frame | seL4_X86_4K | **8** (not 7!) |

## Root Cause: TCBSetSpace CSpace Corruption

CNode diagnostic output:
```
slot2=ffffff801ffa0000 tcbCT=56867fc00ffd0000 tcbCN=7fc00ffd0000
```
- slot2 (extra cap): valid kernel pointer → 0xffffff801ffa0000 ✅
- tcbCT (tcbCTable cap word): garbage → 0x56867fc00ffd0000 ✗
- tcbCN (extracted CNodePtr): user-space → 0x7FC00FFD0000 ✗

TCBSetSpace creates derived CNode cap with CNodePtr in USER-SPACE,
causing GP fault on any subsequent `lookupCapAndSlot(thread, cptr)`.

## BootInfo Parser Bug

`Init_Thread_CNode_Bits` reads 12 instead of 19 (CONFIG_ROOT_CNODE_SIZE_BITS=19)
→ Ada BootInfo record offset mismatch at field 0x88.
→ All untyped slot calculations potentially wrong.

## Verified QEMU Log (Stage 7.2, all tests pass)

```
==== Stage 7: Config Daemon + A/B Boot Manager ====
[S7] T1 PASS: Insufficient clearance rejected
[S7] T2 PASS: Auto-rollback after timeout
[S7] T3 PASS: Config committed
[S7] T4 PASS: Failover A->B
[S7.2] T5 PASS: IPC Top_Secret->Top_Secret allowed
[S7.2] T6 PASS: IPC Secret->Confidential blocked
[S7.2] T7 PASS: Confidential cannot read Secret
[S7.2] T8 PASS: Debug event filtered
[S7.3] Retype TCB at slot 500... → Caught cap fault
[S7.3] Retype TCB at slot 500... → (runs when called before TCBSetSpace)
==== Root Task ready ====
```

## Next Steps (Stage 7.4)

1. Fix BootInfo parser (Init_Thread_CNode_Bits offset)
2. Call Launch_MLS_Server BEFORE TCBSetSpace
3. TCBResume → MLS thread starts
4. seL4_Send IPC test to MLS server endpoint

## Architecture — SEL4_PRIMARY mode

```
GRUB2 (Multiboot2)
  │
  ├── multiboot2 /boot/sel4_kernel.elf    ← seL4 microkernel (Ring 0)
  └── module2   /boot/root_task.elf        ← Ada/SPARK Root Task (Ring 3)

seL4 boots → parses MBI2 → ELF-loads root_task.elf →
creates VSpace/CSpace/TCB → drops to Ring 3 →
Ada code runs: syscalls, BootInfo, UART output ✅
```

## Verified Boot Log (QEMU 2026-08-11)

```
Booting all finished, dropped to user space
==== Schild TCB Root Task (Ada/SPARK 2022) ====
==== seL4 BootInfo Resource Parser ====
Node: 0 / 1                          ← single node
CSpace: 2^19 slots                   ← 524288 capability slots
Untyped: 50 caps                     ← 50 untyped memory regions
----- Memory Map -----
  #0: 0x0000000000000000 .. 0x00100000  1 MB   [dev]
  #1: 0x000000001FFE0000 .. 0x00200000  0 MB   [dev]
  #2: 0x0000000020000000 .. 0x00400000  512 MB [dev]
  #3: 0x0000000040000000 .. 0x00800000  1024 MB [dev]
  #4: 0x0000000080000000 .. 0x00C00000  1024 MB [dev]
  ...
==== Root Task ready ====
0 Caught errors, 0 faults
```

## seL4 Syscall ABI (x86_64, CONFIG_SYSCALL)

```
Register convention:
  RDX  = syscall number (negative: -3=Send, -5=Recv, -6=Reply, -7=Yield, -9=DebugPutChar)
  RDI  = cap register / destination / source
  RSI  = message info
  R10  = MR0, R8 = MR1, R9 = MR2, R15 = MR3

Critical ABI detail:
  RSP saved in RBX before syscall (kernel reads user RSP from RBX)
  RBX is CALLEE-SAVED → must be preserved across the call
  Solution: xchgq %rax, %rbx (swap with caller-saved RAX)
```

### Syscall stub pattern (final)
```asm
schild_sel4_xxx:
    xchgq   %rax, %rbx      ; save RBX → RAX (caller-saved)
    movq    %rsp, %rbx       ; RBX = user RSP for kernel
    movq    $SYSCALL, %rdx   ; syscall number
    syscall
    movq    %rbx, %rsp       ; restore RSP (kernel may modify)
    xchgq   %rax, %rbx       ; restore RBX ← RAX
    ret
```

## Build & Run

```bash
cd src/schild_core

# Full build with Ada root task from source
SEL4_PRIMARY=1 ./build.sh
qemu-system-x86_64 -cdrom sel4_primary.iso -nographic -m 512M -cpu max
```

## Source Files (Root Task — Stage 5)

| File | Lines | Purpose |
|------|-------|---------|
| `tools/sel4/src/schild_sel4_syscalls.S` | 89 | Assembly syscall stubs (6 functions + NBRecv) |
| `tools/sel4/src/schild_sel4_syscall.ads` | 94 | Ada spec — 7 syscall + Retype + TCBSetSpace |
| `tools/sel4/src/schild_sel4_syscall.adb` | 105 | Ada body — Put_String + Init_Fault_Handler |
| `tools/sel4/src/schild_sel4_bootinfo.ads` | 67 | BootInfo record (exact C layout, 50 untyped) |
| `tools/sel4/src/schild_sel4_bootinfo.adb` | 50 | Put_Hex, Put_Dec, Put_Str |
| `tools/sel4/src/schild_root_task.adb` | 93 | Root task — BootInfo + Stage 5 NBRecv loop |
| `tools/sel4/src/rt_start.S` | 28 | Entry: RDI→global, 8KB stack, → Ada |
| `tools/sel4/src/rt_linker.ld` | 7 | Linker: 0x400000, DISCARD .note |
| `tools/sel4/src/message_info.c` | 7 | C: BootInfo ptr + __gnat_rcheck_* stubs |
| `tools/sel4/src/schild_sel4_ipc.c` | 93 | C: IPC buffer ops, MR+extra caps, raw_send |
| `tools/sel4/build_rt.sh` | 46 | User-space ELF build (Ada + C + ASM) |

## Stage 6: TCBSetSpace + Fault Handler (COMPLETED ✅)

### TCBSetSpace ABI (label=11, MCS — supersedes the non-MCS label=10 layout)

```
MR[0] = cRootData (0 = keep existing CSpace)
MR[1] = vRootData (0 = keep existing VSpace)
Extra caps[0] = fault_ep (resolved in the CALLER's CSpace, copied into the TCB)
Extra caps[1] = CSpace root (slot 2 = seL4_CapInitThreadCNode)
Extra caps[2] = VSpace root (slot 3 = seL4_CapInitThreadVSpace)
```

### Verified Boot Log (QEMU 2026-08-11, Stage 6)

```
==== Stage 6: Retype + TCBSetSpace + NBRecv ====
[Stage6] IPC buffer: kernel-managed
[Stage6] Retyping untyped → Notification at slot 100
[Stage6] UntypedRetype -> raw=0x19
[Stage6] Binding fault handler (TCBSetSpace)...
[Stage6] TCBSetSpace -> raw=0x1
[Stage6] Fault handler initialized
[Stage6] Fault handler ready. Entering NBRecv poll loop...
==== Root Task ready ====
```

### Bugs Fixed in Stage 6 (6 total)
| B# | Bug | Fix |
|----|-----|-----|
| B1 | extraCaps at bit 9 instead of bit 7 | `<<9` → `<<7` |
| B2 | MR[0-3] not in registers R10/R8/R9/R15 | register asm constraints |
| B3 | TCBSetIPCBuffer corrupts TCB | removed — kernel sets up |
| B4 | node_depth=19 instead of 0 | `Node_Depth => 0` |
| B5 | Size_Bits=region_size(17) instead of 0 | `Size_Bits => 0` |
| B6 | QEMU Is_Device blocks kernel objects | `#if 0` in untyped.c |

## Next Steps — Stage 7

1. **Config Daemon** — transactional `commit confirmed` + SPARK validation
2. **A/B Boot Manager** — dual root_task with SHA-256 + atomic failover
3. **MLS Policy Daemon** — isolated server, Bell-LaPadula enforcement
4. **Audit Logger** — guaranteed audit event delivery

### seL4 Object Invocation ABI

```
Invocation via SysSend(-3) or SysCall(-1):
  RSI = message info  (label<<12 | extraCaps<<9 | length)
  R10 = MR[0], R8 = MR[1], R9 = MR[2], R15 = MR[3]
  MR[4+] in IPC buffer at word offset 1+N
  Extra caps at word offset seL4_MsgMaxLength + 2 + N (= 122+N)
```

### Method labels (MCS — see `docs/technical/MCS_MIGRATION.md` for the full table)

| Label | Method | Extra Caps |
|-------|--------|------------|
| 1 | UntypedRetype | 1 (root CNode) |
| 10 | TCBSetIPCBuffer | 1 (buffer frame) |
| 11 | TCBSetSpace | 3 (fault_ep, cspace, vspace) |
| 13 | TCBResume | 0 |
| 22 | CNodeMint | 1 (src CNode) |
| 33 | SchedControlConfigureFlags | 1 (schedcontext) |
| 34 | SchedContextBind | 1 (TCB) |

### Known Issue: CONFIG_FASTPATH (non-MCS only; resolved on MCS)

On x86_64 with CONFIG_FASTPATH, extra caps not resolved —
`excaprefs[0] == NULL` → `seL4_TruncatedMessage`.
**Fix for Stage 6 (non-MCS):** rebuild seL4 kernel with `CONFIG_FASTPATH=n`.
**MCS (W5, 2026-10-04):** `KERNEL_FASTPATH=ON KERNEL_MCS=ON` → 18/18, no
TruncatedMessage — the bug was non-MCS-specific (see ROADMAP §W5).

## 7 Critical Bugs Fixed

| # | Bug | Symptom | Fix |
|---|-----|---------|-----|
| 1 | GRUB places module in ELF gap | `mods_end_paddr > ki_p_reg.end` | PT_LOAD[1] memsz extension |
| 2 | `hlt` in Ring 3 | #GP exception | `pause` instruction |
| 3 | C prologue corrupts stack (RSP=0) | Page fault | 8KB stack in `.bss` |
| 4 | `call` without stack | Page fault at 0xFFFFFFFFFFFFFFF8 | `leaq rt_stack_top, %rsp` |
| 5 | RBX clobber → segfault | `sub %rbx, %rdx` corruption | `xchgq %rax, %rbx` |
| 6 | `push %rbx` + `pop %rbx` → ret wrong | Return to data section | RAX-based save |
| 7 | `.note.gnu.property` overlaps `.text` | Code execution in .rodata | Custom linker: `/DISCARD/` |

## Memory Layout (SEL4_PRIMARY mode)

```
0x000000-0x100000   BIOS/GRUB
0x100000-0x80150C   seL4 kernel (contiguous, gap closed!)
0x80150C-0xA21800   seL4 .text main kernel
0xA22000-0xA25000   Root Task image (loaded by seL4)
0x404000            BootInfo frame (mapped by seL4, RDI at entry)
0x403000            IPC buffer (seL4-managed)
0xA25000+           Untyped Memory (~500MB managed by seL4)
```

## Next Steps — Stage 5

1. **Untyped_Retype** — syscall binding for memory allocation
2. **TCB creation** — retype untyped → TCB objects
3. **Init Manager spawn** — launch Schild TCB kernel as child process
4. **MLS servers** — Root Task spawns security server chain
