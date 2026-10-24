# e1000e + TCP/IP migration from Ring 0 to Ring 3 — plan (historical)

**Version:** Stage 8.1  |  **Date:** 2026-08-13 (updated 2026-10-04)
**Developer:** Ирганов А.Н.

> **Status: ✅ COMPLETE (Stage 8.1A–D + W2).** All four stages are done and
> verified in QEMU (0 faults); **W2** then moved the NetServer to the real
> I219-V (ECAM-scan + MSI, `0xE8200000`), validated end-to-end on the T580.
> e1000e + TCP/IP run in the isolated Ring 3 NetServer process over seL4 IPC.
> See `CHANGELOG.md` / `ROADMAP.md` for the canonical current state.

## 1. Goal

Move the e1000e driver + TCP/IP stack out of Ring 0 (standalone kernel, `.bss`)
into an isolated seL4 Ring 3 process ("NetServer") that talks to the
Root Task only over seL4 IPC. This removes a major architectural
debt: the network currently runs in a privileged context.

## 2. Current state (Ring 0)

```
Schild_Kernel_Entry (standalone, Ring 0)
  └─ if Schild_E1000e.Is_Ready then
       Schild_Net_Stack.Init; Schild_Net_Stack.Run_Loop;  -- busy-poll
```

Driver (`src/01_hardware/schild_e1000e.adb`):
- PCI scan `Find_Device` → `Info.BAR0` (physical MMIO, QEMU ~0xFEB00000).
- `C_Map_MMIO` = `schild_map_mmio_2mb` (runtime_stubs.c) — **identity-maps**
  BAR0 through `pd_table2` (PDPT[3], 3–4 GB), then `MMIO := BAR0`.
- DMA buffers `Tx_Ring/Rx_Ring/Tx_Buf/Rx_Buf` — static arrays in `.bss`;
  their addresses are given to the card as **physical** (`C_Addr` → `schild_ptr_to_u64`),
  because the kernel is identity-mapped.
- Cache coherence: `wbinvd`/`clflush` (needed on real T580).

Stack (`src/04_userland/schild_net_stack.adb`):
- `Run_Loop` → `Schild_E1000e.Poll_Rx` → EtherType dispatcher → ARP/IPv4/ICMP/TCP/HTTP.
- ARP/ICMP/TCP/HTTP — pure functions (no MMIO), depending only on
  `Schild_Net_Types` and frame send/receive.

## 3. Target architecture (Ring 3)

```
┌ Ring 0 — seL4 kernel ─────────────────────────────┐
│  (device-memory untyped for BAR0 already in BootInfo) │
└────────────────────────────────────────────────────┘
┌ Ring 3 — Root Task (Top_Secret) ──────────────────┐
│  · Retype device-untyped(BAR0) → Frame             │
│  · PageMap Frame → NetServer VSpace                │
│  · TCBSetIPCBuffer(NetServer, own frame)           │
│  · Launch NetServer (TCB + SetSpace + WriteRegs)   │
│  · Endpoint "net_ep" for IPC                       │
└────────────────────────────────────────────────────┘
         │ seL4 IPC (Call/Reply, endpoint "net_ep")
┌ Ring 3 — NetServer (Internal) ────────────────────┐
│  · Schild_E1000e (Ring 3, MMIO via mapping)       │
│  · Schild_Net_Stack (ARP/IPv4/ICMP/TCP/HTTP)       │
│  · Recv(net_ep) → process packet → Reply           │
└────────────────────────────────────────────────────┘
```

## 4. Key problems → solutions

| # | Problem | Solution |
|---|----------|---------|
| P1 | Driver is identity-mapped (virtual address = physical) | In Ring 3, separate the notions: the **virtual** address of MMIO/buffers (for the CPU) and the **physical** one (for DMA descriptors). The Root Task passes the physical DMA-frame address to NetServer over IPC. |
| P2 | MMIO BAR0 unreachable from Ring 3 | Root Task does `UntypedRetype(device-untyped@BAR0 → Frame)` + `X86PageMap` into the NetServer VSpace. device-untyped is already available thanks to the device-bypass patch. |
| P3 | DMA buffers must be physically contiguous and known to the card | Allocate a dedicated Frame (from RAM untyped) for the ring descriptors+buffers; NetServer writes the **physical** address it got from the Root Task into the descriptors. |
| P4 | Shared IPC buffer (hack: MLS reads the Root Task buffer) | `TCBSetIPCBuffer` for each process — its own Frame. ✅ **Resolved** (Stage 8.1). |
| P5 | busy-poll `Run_Loop` blocks the kernel | In Ring 3 NetServer runs its own Recv/Reply loop; the Root Task polls on a timer/IPC. |
| P6 | e1000e interrupts (IRQ) in Ring 0 | Stage 1 — **polling** (no IRQ, as in QEMU today). IRQ delivery via seL4 Notification is a separate stage. |

## 5. Implementation stages

### Stage A — Process infrastructure (doable now)
1. Generalize `Launch_MLS_Server` → `Launch_Process (EP_Slot, TCB_Slot, Entry, Stack, ...)`.
2. `TCBSetIPCBuffer`: allocate a dedicated Frame for the process IPC buffer,
   `PageMap` into its VSpace, `TCBSetIPCBuffer`. Remove the "shared buffer" hack.
   ✅ **Resolved** (Stage 8.1) — a dedicated RAM frame + `PageMap` + `TCBSetIPCBuffer`
   work; the IPC test is green.

### Stage B — MMIO BAR0 mapping
3. In the Root Task: find the device-untyped for `Info.BAR0` (the PCI scan stays in
   the Root Task, or BAR0 is passed in from outside), `UntypedRetype → X86_4K Frame`,
   `X86PageMap` into the NetServer VSpace at an agreed vaddr (e.g. 0x600000).
4. NetServer uses MMIO at that vaddr.
   ✅ **Resolved** (Stage 8.1B) — `Map_NetServer_MMIO` in `schild_sel4_syscall.adb`:
   device-untyped localization (QEMU `0xFE800000`, offset 768 → BAR0 `0xFEB00000`),
   retype 800×4K frames (in chunks of 256), `X86PageTableMap`(37) for the PT in
   `[0x600000,0x800000)`, then `X86PageMap`(39) of 32 frames at `0x600000`.
   Driver: added `Init_MMIO (MMIO_VAddr)` (Ring 3 path, no PCI scan/`schild_map_mmio_2mb`/IOAPIC).
   Verified in QEMU: `NetServer MMIO map: OK`, 0 faults.

### Stage C — Stack migration
5. Compile `schild_e1000e` + `schild_net_*` into `root_task.elf` as Ring 3
   code (there is already a precedent: the MLS server in C).
6. Split virtual/physical addresses in the driver.
   ✅ **Resolved** (Stage 8.1C) — the driver + the whole `schild_net_*` (ARP/IPv4/ICMP/TCP/HTTP)
   + `Schild_Schild_Fs` + `Schild_Nvme` are compiled into `root_task.elf` and work
   in Ring 3: `Init_MMIO(0x600000)`, DMA descriptors write **physical** addresses
   (`schild_dma_phys` = virtual + offset 0x621000), `Schild_Net_Stack.Init` prints
   `[NET] Stack ready`. Fixed `schild_http_server` (fixed `Path_String`,
   removed secondary stack). Verified in QEMU: 0 faults.
   Remaining: run `Run_Loop` in a separate NetServer thread + IRQ via Notification.

### Stage D — IPC contract + integration
7. Endpoint `net_ep`; when a packet arrives the Root Task sends a "poll" request,
   NetServer replies with the processing result (or dumps the raw frame).
   ✅ **Resolved** (Stage 8.1D) — NetServer launched as a separate process
   (`netserver.c` + `netserver.S`, endpoint `net_ep`@502, TCB@201, IPC buffer@204
   at 0x510000). Contract: MR[0]=op (0=init, 1=poll_rx), Reply MR[0]=status.
   Root Task `Call`(op=init) → NetServer `Recv` → `schild_net_init` (Init_MMIO +
   Net_Stack.Init) → `Reply status=0`. Verified in QEMU: 0 faults.
   Remaining: IRQ via seL4 Notification (currently polling) + large-frame
   transfer via a shared DMA frame (not via MR).

## 6. IPC contract (preliminary)

- **Root Task → NetServer** (`Call` on `net_ep`):
  MR[0] = op: 0=poll_rx, 1=send_frame, 2=init
  MR[1] = parameter (for send — buffer pointer/length)
- **NetServer → Root Task** (`Reply`):
  MR[0] = status (0=ok, 1=no packet, 2=error)
  MR[1] = length of the received/processed frame

(Real large-frame transfer is via a shared DMA frame, not MR.)

## 7. Memory map (QEMU)

| Object | Physical address | Virtual (Ring 3) |
|--------|------------------|----------------------|
| e1000e BAR0 | ~0xFEB00000 (128 KB) | 0x600000 (agreed) |
| DMA ring+bufs | RAM untyped (Frame) | 0x601000 (agreed) |
| IPC buffer NetServer | RAM untyped (Frame) | 0x602000 (agreed) |

## 8. Stage 1 limitations

- Polling instead of IRQ (as the current QEMU mode).
- HTTP/TCP are already checked for compile correctness, but RX in QEMU
  (user-mode network) does not deliver packets — verification on real hardware/another
  network backend.

## 9. Resolved: dedicated IPC buffer (TCBSetIPCBuffer + PageMap)

> **Status: RESOLVED (Stage 8.1).** It was previously thought to be a cache/TLB
> coherence problem — the diagnosis turned out to be **wrong**.

The real cause is the seL4 x86_64 ABI, not memory coherence:

- On x86_64 `n_msgRegisters == 4`, and `copyMRs()`/`setMR()` deliver
  **MR[0..3] in the hardware registers R10/R8/R9/R15** (`msgRegisters[]`), while
  **only MR[4+]** are written into the IPC buffer (`recvBuf[i+1] = sendBuf[i+1]`).
  See `src/object/tcb.c` (`copyMRs`) and `include/object/tcb.h` (`setMR`).
- The MLS server read `ipc[1]`/`ipc[2]` (= MR[0]/MR[1]) from the buffer, where the
  kernel **never wrote them** → 0 remained there. This was mistakenly taken for
  "the kernel write is not visible through the user mapping".
- The "shared buffer" worked only because MLS read the **Root Task** buffer
  (where the Root Task itself had written `b[1]=mr0; b[2]=mr1` before the Call),
  i.e. entirely bypassing seL4 IPC.

Fix (Stage 8.1):

- `schild_sel4_syscalls.S`: the `Recv`/`NBRecv` stubs capture MR[0..3]
  from R10/R8/R9/R15 into `schild_recv_mr[]`; `Reply` loads MR[0..3] from
  `schild_reply_mr[]` back into registers.
- `schild_sel4_ipc.c`: `schild_sel4_call` captures reply MRs from
  R10/R8/R9/R15 into `schild_call_mr[]`; `schild_read_ipc_mr0` reads from there.
- `mls_server.c`: reads `schild_recv_mr[0]`/`[1]`, writes the reply into
  `schild_reply_mr[]`.
- `schild_sel4_syscall.adb` (`Launch_MLS_Server`): allocated a **dedicated
  RAM frame** (untyped with `Is_Device=0`), `UntypedRetype→4K`, `PageMap` at
  0x500000, `TCBSetIPCBuffer`. The "shared buffer" hack removed.

Verification (QEMU, `sel4_primary.iso`): `IPC Call... 1`,
`Reply MR0 (result): 0`, `==== Root Task ready ====`, 0 faults.

> Kernel-window (PPTR) vs user-mapping coherence on x86 is guaranteed
> by hardware (physically tagged caches) — a cache flush for IPC is **not needed**.

## 10. Progress (Stage 9 — NetServer isolation + RX path)

> **Status: FULL ISOLATION + REAL HARDWARE ACHIEVED (W2).** NetServer is a
> true seL4 process: own CSpace (CNode) + own VSpace (ASID-bound PML4). The
> real I219-V (`0xE8200000`) is driven via ECAM + MSI (IRQ-driven RX, badge
> `0xE1`); end-to-end TCP/HTTP validated on the T580.

### Done
- ✅ **Parser in NetServer** (P1-8). `Schild_Net_Stack.Poll_And_Process` — the full
  EtherType dispatcher is called from `Net_Poll` instead of discarding the frame.
- ✅ **CSpace isolation** (P0-1). Own CNode (`schild_sel4_cnode_mint`,
  label 21): only `net_ep` and the fault cap. root-CNode depth = 64 (wordBits),
  the CPtr of a retyped CNode slot = `N << 60` (guardSize=0).
- ✅ **VSpace isolation** (P0-1). Own ASID-bound PML4 (1 PDPT +
  1 PD + 2 PT): image (mint-duplicated frames, 36 pages), IPC buffer and MMIO are mapped.

### Steps (remaining)
1. **IRQ via seL4 Notification** (replacing polling). The Root Task retypes
   an IRQ handler for e1000e and binds it to a Notification.
2. **Large frames via a shared DMA frame.** MR[0..3] live in registers,
   so large frames go through a shared Frame (ring+buffers).
3. ✅ **RX validation on real hardware (W2, DONE).** The root task discovers
   the I219-V (`8086:15d8`) via ECAM, programs MSI, maps BAR0 (`0xE8200000`);
   the NetServer serves end-to-end TCP/HTTP on the T580 (IRQ-driven RX, badge
   `0xE1`).
4. **Kernel**: ✅ `tcb-mdb` reverted (P0-2, root cause = object-zeroing RC1); IOMMU still to enable.

