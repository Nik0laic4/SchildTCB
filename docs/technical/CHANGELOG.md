# Schild TCB — Engineering Changelog

**Developer:** Ирганов А.Н.

> Policy: this changelog records **verified results only**. Items marked
> *pending* or *target* have not yet been validated. Formal-verification
> coverage is stated per-module, never as an aggregate percentage.

## v1.0.0-pre (2026-10-25) — AArch64: reproducible validation harness

**Validated: `run_net_test.py` (committed) builds the root task + child ELF, injects the root task into the elfloader, rebuilds the image, runs QEMU with the host HTTP/TCP services, polls the serial log for the success marker and exits 0/1 (`[harness] PASS: virtio-net E2E in an ELF child (own VSpace)`, ~5 s once the marker appears).**

- `run_net_test.py`: self-contained harness (build → strip → ninja → QEMU → poll the success/fail marker), with `--skip-build`, `--sel4-build-dir`, `--timeout`.
- The SLIRP backend remains; a deterministic `-netdev socket`/tap backend is the follow-on (SLIRP is IRQ-noisy).

## v1.0.0-pre (2026-10-25) — AArch64: minimal TCP ACK of received data

**Validated: the HTTP client now ACKs the received HTTP/1.0 response (ack = seq + len), so the SLIRP peer stops retransmitting (`[ack]` marker printed; the full stack still passes `virtio-net: OK (own VSpace + ELF child)`).**

- `net_test.c`: after receiving the HTTP response body, send a minimal pure-ACK segment (flags `ACK`, `ack = seq2 + pl2`) on the client's sequence; the file header no longer claims "received TCP data is not ACKed".

## v1.0.0-pre (2026-10-25) — AArch64: virtio-net driver + protocol in an ELF child process (own VSpace)

**Validated: the virtio-net driver + full protocol stack (ARP→ICMP→DHCP→TCP/HTTP→TCP server→DNS) now run in a child process with its OWN VSpace; the root brings the device up, hands the device MMIO + DMA frame to the child's VSpace (unmap + remap), and the child re-attaches from a fixed layout and drives the device (`virtio-net: OK (own VSpace + ELF child)`, with `[body] SchildTCB-body`, `[dns] ...`, `[irq] N`).**

- `sel4_mmio.c`: `schild_map_mmio`/`alloc_dma_2m` now record the device/DMA large-page caps (`dev_page_cap`/`dma_page_cap`) for remap.  Added `schild_net_elf_child_main` (child entry: re-attach driver state from the fixed handoff layout, derive the DMA PA from RX descriptor 0, run IRQ + protocol, signal) and `schild_net_elf_child_test` (root: device init → child VSpace → page tables → unmap/remap device + DMA into the child VSpace → load ELF → IPC-buffer frame → CSpace grants → child TCB with its own VSpace + IPC buffer → wait).
- `build_root.sh`: the child ELF is built from the same `sel4_mmio.c` + `net_test.c` + `sel4_stubs.c` sources with `-ffunction-sections -fdata-sections --gc-sections`, dropping the root-only platform code (BootInfo/MMIO-map/child-spawn/VSpace loader) and keeping only the driver + protocol + syscall shims.
- `schild_arm_root_task.adb`: calls `schild_net_elf_child_test`; the shared-VSpace net child and the minimal ELF demo are superseded.
- The child's IPC buffer is a dedicated 4 KiB frame mapped at 0x900000 in the child VSpace and passed to `TCB_Configure` as `buffer`/`bufferFrame`.

## v1.0.0-pre (2026-10-25) — AArch64: child process in its own VSpace (separate page table + ELF loader)

**Validated: the root task creates a separate VSpace (VSpaceObject + ASID pool + ASID assignment), loads a self-contained child ELF into it (code RX / data RW+NX, cacheable) and runs the child TCB with its own CSpace + VSpace; the child prints from its own address space and signals badge 42 (`[elf] child process running in its own VSpace`, `elf child: OK (separate VSpace + ELF)`), while the net child test keeps passing (`virtio-net DNS: OK (child)`).**

- `sel4_mmio.c`: added the VSpace/ELF machinery — `vspace_new` (VSpaceObject retype + `ARMASIDControlMakePool` + `ARMASIDPoolAssign`), `map_page_table` / `map_frame` / `unmap_frame`, `elf_load_segment` (a 4 KiB frame per page, filled via a root-VSpace scratch mapping at `COPY_VA`, then mapped RX or RW+NX), and `schild_elf_child_test` (VSpace + 3-level page-table setup + ELF load + child TCB with its own CSpace/VSpace + wait for badge).  AArch64 object types / invocation labels / rights / attributes are now named constants.
- `child_main.c` + `child_start.S` + `child_linker.ld`: a minimal child process (DebugPutChar + signal slot 0), linked at 0x400000 with RX/RW segment separation.
- `build_root.sh`: builds `obj_child/child.elf` and embeds it into the root ELF via `.incbin`.
- `schild_arm_root_task.adb`: runs `schild_elf_child_test` after the net child test and reports the badge.
- Gotchas fixed: the net child (same ELF, shared data) clobbers the file-scope `ipc_buf`, so the root restores it before its own syscalls; `seL4_CanRead` is bit 1 (value 2), not bit 0.

## v1.0.0-pre (2026-10-24) — AArch64: virtio-net driver in an isolated child domain

**Validated: the driver IRQ path + protocol stack run in a child TCB with its own CSpace (16-slot CNode: self CNode + RAM untyped + IRQ handler + VSpace + result notification), sharing the device MMIO/DMA/queues initialized by the root; the child reports its result via a cross-domain notification (`virtio-net DNS: OK (child)`, `[irq] 31–49`).**

- `sel4_mmio.c`: split `virtio_net_init` into `virtio_net_init_device` (MMIO/DMA/queues/DRIVER_OK) + parameterized `virtio_net_init_irq(struct irq_ctx *)` (IRQ notification + waiter TCB in a given CSpace context).  Added `schild_spawn_net_child` (grants self CNode, RAM untyped, IRQ handler, VSpace, result notification) and `schild_net_child_main` (child entry: IRQ init + test + signal).
- `net_test.c`: split `schild_virtio_net_test` into `schild_virtio_net_run_test` (protocol only) + a wrapper.
- Child CSpace isolation: the child can only invoke caps in its 16-slot CNode (shared VSpace for now).  The child uses its own IPC buffer (within its 2 MiB stack page).


## v1.0.0-pre (2026-10-24) — AArch64: child-domain isolation demo (own CSpace + cross-domain signal)

**Validated: the root task spawns a child TCB with its OWN CSpace (a fresh 8-slot CNode containing only a badged result notification) and a shared VSpace; the child signals its slot 0 and the root observes badge 42 (`child round-trip: OK`, `[child] 42`).**

- `sel4_mmio.c`: `schild_spawn_child` retypes a CNode (`seL4_CapTableObject`),
  a result notification, a 2 MiB stack page and a TCB; mints the notification
  into the child CNode slot 0 (badge 42), configures the child TCB with its own
  CSpace (shared VSpace), and starts it via `TCB_WriteRegisters`.
  `schild_child_wait` blocks on the result notification.
- `net_test.c` + `schild_arm_root_task.adb`: `schild_child_test` spawns + waits
  and reports the badge over UART.
- Gotchas fixed: a CNode's `UntypedRetype` size_bits is the radix (not
  radix+SlotBits); a 4 KiB small-page mapping needs an intermediate page table,
  so the child stack uses a 2 MiB block mapping instead.


## v1.0.0-pre (2026-10-24) — AArch64: virtio-net driver/test split (reusable API)

**Validated: the monolithic `sel4_mmio.c` was split into a reusable virtio-net driver (`virtio_net.h` API: `init` / `tx_buffer` / `tx_send` / `rx` / `rx_done`) and a separate protocol test (`net_test.c`); the full stack still passes (`virtio-net DNS: OK`, `[irq] 138–176` across runs).**

- `virtio_net.h` exposes the driver API; `sel4_mmio.c` keeps the platform layer
  (syscall shims, object retype, MMIO map) plus the driver implementation; the
  protocol builders/parsers and `schild_virtio_net_test` moved to `net_test.c`.
- `rx_wait`/`rx_poll`/`rx_frame`/`rx_recycle` collapsed into blocking
  `virtio_net_rx` / `virtio_net_rx_done` (frame-based, no descriptor ids);
  `tx_send` became blocking `virtio_net_tx_send` (void).


## v1.0.0-pre (2026-10-24) — AArch64: virtio-net IRQ waiter thread (blocking seL4_Wait)

**Validated: the IRQ notification is now consumed by a dedicated waiter TCB that blocks with `seL4_Wait`, Acks the IRQ, and signals the main thread; the main thread blocks instead of polling (`virtio-net DNS: OK`, `[irq] 102–220` across runs).**

- `sel4_mmio.c`: added a second TCB (retype + `TCB_Configure` + `TCB_WriteRegisters`), a second notification (`main_ntfn`), and the `irq_waiter` loop (`seL4_Wait` → `IRQHandler_Ack` → `seL4_Signal`).  `irq_poll` now blocks on `main_ntfn`.
- Replaced the non-blocking `seL4_NBRecv` poll with blocking `seL4_Wait` — no busy-poll left in the IRQ path.
- The waiter thread's stack reuses an unused region of the 2 MiB DMA frame; no separate IPC buffer is needed (Ack/Signal/Wait carry no message).


## v1.0.0-pre (2026-10-24) — AArch64: virtio-net IRQ via seL4 Notifications (QEMU)

**Validated: the virtio-net IRQ (GIC SPI 47 = GIC IRQ 79) is bound to a seL4 Notification and polled non-blockingly + Acked; the full stack passes end-to-end (`virtio-net DNS: OK`, `[body] SchildTCB-body`, `[dns] ...`, `[irq] 75–151` across runs).**

- `sel4_mmio.c`: `net_init` retypes a notification object, mints it badged with
  the IRQ (79) via `CNode_Mint` (label 21), then `IRQControl_Get` (label 26) +
  `IRQHandler_SetNotification` (label 28).  `irq_poll` does `seL4_NBRecv`
  (syscall -8) → ISR read (0x060) → `IRQHandler_Ack` (label 27).
- `tx_send`/`rx_wait` and the TCP-server/DNS search loops now wait on the
  notification instead of busy-reading the used ring; the used-ring drain is
  retained as a safety net (single-threaded root task → `seL4_Poll`, non-
  blocking; a blocking `seL4_Wait` needs a second thread).
- Validated under the same QEMU `-netdev user` + `hostfwd` harness.


## v1.0.0-pre (2026-10-24) — AArch64: virtio-net descriptor-ring refactor (QEMU)

**Validated: the seL4 root task's virtio-net driver now uses honest split-ring management (RX buffer pool + rotating TX descriptors) instead of re-arming descriptor 0; the full stack still passes end-to-end (`virtio-net DNS: OK`, `[body] SchildTCB-body`, `[dns] ...`).**

- `sel4_mmio.c`: replaced the manual `descriptor 0` re-arm with `net_init()` +
  ring helpers (`rx_post`, `rx_poll`/`rx_wait`, `rx_recycle`, `tx_buffer`/
  `tx_send`); `avail_idx`/`used_idx` now advance monotonically.
- DMA frame re-laid out: RX desc/avail `0x0000`, RX used `0x1000`, 4× RX
  buffers (`0x2000 + d·0x1000`), TX desc/avail `0x6000`, TX used `0x7000`,
  4× TX buffers (`0x8000 + d·0x1000`).
- The used ring's per-entry descriptor id now selects the RX buffer (no
  hardcoded descriptor 0); consumed RX buffers are recycled through the avail
  ring.
- Busy-poll is retained; IRQ routing via seL4 Notifications is the remaining
  driver step (separate task — needs `-netdev socket`/tap because QEMU SLIRP
  delivers interrupts unreliably).


## v1.0.0-pre (2026-10-24) — AArch64: virtio-net DNS client under seL4 (QEMU)

**Validated: the Ada seL4 root task sends a DNS A query for `example.com` (UDP, `53000 → 10.0.2.3:53`) and parses the A-record answer (`virtio-net DNS: OK`, `[dns] 8.6.112.0`).**

- `sel4_mmio.c`: DNS query builder (header + QNAME + QTYPE/QCLASS), UDP frame
  to the SLIRP DNS server, and a reply parser (ID + QR + ANCOUNT, extracting
  the last A record's RDATA).
- QEMU's SLIRP forwards `10.0.2.3:53` to the host resolver; the reply carries
  two A records (the environment's resolver returns filter IPs), and the last
  one is printed over UART.
- Full stack now covers ARP, ICMP, DHCP, TCP client/server, HTTP and DNS.
- Next step: driver refactoring (interrupts / descriptor ring), or proper TCP
  ACKs of received data.

## v1.0.0-pre (2026-10-24) — AArch64: virtio-net TCP server under seL4 (QEMU)

**Validated: the Ada seL4 root task passively opens a TCP connection on port 8081 (SYN → SYN-ACK → ACK) to a host client forwarded through SLIRP `hostfwd` (`virtio-net TCP server: OK`).**

- `sel4_mmio.c`: `build_tcp_frame` now takes explicit sport/dport; the server
  arm parses the incoming SYN (client ISN + port) and replies with SYN-ACK
  (server ISN `0x87654321`), then verifies the client ACK.
- The RX loop skips the HTTP server's retransmissions (we never ACK the HTTP
  response) by filtering on destination port 8081 and re-arming buffers.
- Validated with `-netdev user,hostfwd=tcp::8081-:8081` + a Python client
  (`connected OK`); pcap shows `[S]` → `[S.]` → `[.]` on 8081.
- Full stack now covers both client and server roles over virtio-net.
- Next step: a DNS-over-UDP client, or driver refactoring (interrupts / ring).

## v1.0.0-pre (2026-10-24) — AArch64: virtio-net HTTP client + body parse under seL4 (QEMU)

**Validated: the Ada seL4 root task sends `GET / HTTP/1.0` over a TCP connection to a host HTTP server via the SLIRP gateway, receives `HTTP/1.0 200 OK`, and prints the response body over UART (`virtio-net HTTP: OK`, `[body] SchildTCB-body`).**

- `sel4_mmio.c`: the TCP data payload is now an HTTP/1.0 request; the response
  verifier checks the payload for the `HTTP/` prefix, then `print_http_body`
  locates the `\r\n\r\n` separator and prints the body over UART.
- The server replies with a pure ACK first, then the HTTP response, so the RX
  queue is armed with **two** buffers (descriptors 0 and 1) for the data round.
- Validated against `python3 -m http.server` and a minimal Python server
  returning a fixed `Content-Length` body in a single segment.
- Full stack in one boot: ARP → ICMP → DHCP → TCP handshake → HTTP GET/response.
- Next step: a TCP server (guest listens on a port) or a DNS-over-UDP client.

## v1.0.0-pre (2026-10-24) — AArch64: virtio-net TCP client under seL4 (QEMU)

**Validated: the Ada seL4 root task completes a TCP 3-way handshake (SYN → SYN-ACK → ACK) to a host service via the SLIRP gateway (`10.0.2.2:8080`) and exchanges data (`virtio-net TCP: OK`).**

- `sel4_mmio.c`: TCP segment builder (20-byte header + IPv4 pseudo-header
  checksum), generic TCP parser (seq/ack/flags/payload), 3-way handshake and a
  data exchange (`ping` → `host-ack`) against a Python server on the host.
- QEMU's SLIRP forwards the gateway `10.0.2.2` to the host loopback, so the
  guest reaches a host service directly — deterministic, no internet required.
- Full stack now validated in one boot: ARP → ICMP echo → DHCP DISCOVER/OFFER
  → TCP handshake + data round-trip.
- Next step: an HTTP client (TCP + HTTP/1.0 GET) and, later, a TCP server.

## v1.0.0-pre (2026-10-24) — AArch64: virtio-net DHCP (UDP) under seL4 (QEMU)

**Validated: the Ada seL4 root task sends a DHCP DISCOVER (UDP broadcast, `0.0.0.0:68` → `255.255.255.255:67`) and receives the DHCP OFFER (`Your-IP 10.0.2.15`) from QEMU's SLIRP server (`virtio-net DHCP: OK`).**

- `sel4_mmio.c`: UDP datagram builder (8-byte header + IPv4 pseudo-header
  checksum), 300-byte BOOTP/DHCP DISCOVER builder (op=1, flags=broadcast,
  chaddr=MAC, cookie, option 53 = DISCOVER), and a DHCP OFFER parser
  (op=BOOTREPLY, UDP dport 68, yiaddr extraction).
- Full stack now validated end-to-end in one boot: ARP resolution → ICMP echo
  (ping) → DHCP DISCOVER → DHCP OFFER, re-arming the RX/TX queues between each
  round-trip.
- This removes the hardcoded guest IP path; next step is a TCP client
  (3-way handshake) over the DHCP-leased address.

## v1.0.0-pre (2026-10-24) — AArch64: virtio-net ICMP echo (ping) under seL4 (QEMU)

**Validated: the Ada seL4 root task resolves the gateway via ARP and completes an ICMP echo round-trip (`virtio-net ping: OK`).**

- `sel4_mmio.c`: 16-bit one's-complement checksum, IPv4 header + ICMP echo
  request builders, ARP-reply parser (gateway MAC) and ICMP-reply verifier.
- Full flow: ARP request → ARP reply (gateway MAC `52:55:0a:00:02:02`) → ICMP
  echo request → ICMP echo reply, with the RX/TX queues re-armed between the
  two round-trips.
- QEMU's user-mode netdev answers `IP 10.0.2.2 > 10.0.2.15: ICMP echo reply`
  (confirmed via `-object filter-dump`).
- This completes the minimal TCP/IP stack (ARP + ICMP echo) for connectivity
  validation under seL4; next step is the higher-level stack (UDP/TCP).

## v1.0.0-pre (2026-10-24) — AArch64: virtio-net RX (ARP round-trip) under seL4 (QEMU)

**Validated: the Ada seL4 root task sends an ARP request for the SLIRP gateway (10.0.2.2) and receives the ARP reply through the RX virtqueue used ring (`virtio-net TX+RX: OK`).**

- `sel4_mmio.c`: prepends the 10-byte `virtio_net_hdr` to RX/TX buffers
  (`len = 10 + frame`) — the missing piece; without it the device treated the
  first 10 bytes of the Ethernet frame as the header and sent a truncated frame.
- RX flow validated end-to-end: empty RX buffer (flags=WRITE) → kick RX →
  kick TX (ARP request) → poll TX used ring → poll RX used ring → verify the
  received frame is an ARP reply (EtherType 0x0806, opcode 2).
- QEMU's user-mode netdev answers with
  `ARP, Reply 10.0.2.2 is-at 52:55:0a:00:02:02` (confirmed via
  `-object filter-dump`).
- Next: a minimal TCP/IP stack (ARP cache + ICMP echo) over virtio-net.

## v1.0.0-pre (2026-10-24) — AArch64: virtio-net virtqueue TX under seL4 (QEMU)

**Validated: the Ada seL4 root task sets up RX + TX virtqueues in a DMA frame, submits a small Ethernet frame, and the virtio-net device consumes it (TX used ring advances, `virtio-net TX: OK`).**

- `sel4_mmio.c`: DMA frame (retype RAM untyped → 2 MiB `LargePage` → map), split
  virtqueues (descriptor/available/used rings), device init (features →
  FEATURES_OK → queues → DRIVER_OK), kick, used-ring poll.
- Discovered: QEMU's virtio-mmio reports **Version=1 (legacy)**, so the queues
  use `GuestPageSize` (0x028) + `QueueAlign` (0x03c) + `QueuePFN` (0x040), not
  the modern `QueueReady`/`QueueDesc` registers.  Writing `GuestPageSize` was
  the missing piece for TX to complete.
- Next: receive packets (RX) and build a TCP/IP stack.

## v1.0.0-pre (2026-10-24) — AArch64: virtio-net MMIO mapped into the seL4 VSpace; MAC read under seL4

**Validated: the Ada seL4 root task maps the virtio-mmio device region into its VSpace and reads the virtio-net MAC (`52:54:00:12:34:56`) under seL4 in QEMU.**

- `sel4_mmio.c`: minimal seL4 object-management sequence — parse BootInfo →
  find device untyped → `Untyped_Retype` (2 MiB `LargePage`) → `ARM_Page_Map`
  (into the root VSpace) → read.  `root_start.S` saves the BootInfo/IPC pointers.
- The root task now prints `virtio-net MAC = ...` after the banner.
- Discovered: this build is **non-MCS** (`CONFIG_KERNEL_MCS` disabled), so the
  BootInfo has no `schedcontrol` field (untyped @ offset 152) and the `Call`
  syscall has no reply register (x6); labels `UntypedRetype=1`, `ARMPageMap=40`;
  object type `seL4_ARM_LargePageObject=8`.
- Next: set up the virtqueues for real TX/RX.

## v1.0.0-pre (2026-10-24) — AArch64: virtio-mmio driver + virtio-net MAC probe (QEMU)

**Validated: the Ada virtio-mmio driver brings a virtio-net device into the DRIVER state and reads its MAC address in `qemu-system-aarch64`.**

- `virtio_mmio.ads` / `virtio_mmio.adb`: virtio-mmio transport driver (spec
  `SPARK_Mode => On`, MMIO body `Off`), overlaying the device registers at the
  qemu virtio-mmio slot.  QEMU attaches the first `-device` to the **last**
  slot (bus.31 @ `0x0a00_3e00`), discovered via `info qtree`.
- `virtio_probe.adb` + `build_virtio.sh`: boots bare-metal and prints
  `virtio-net found, MAC = 52:54:00:12:34:56` (the MAC passed to
  `-device virtio-net-device,mac=...`).
- Next: map the virtio-mmio region into the seL4 root-task VSpace, then set up
  the virtqueues for TX/RX.

## v1.0.0-pre (2026-10-24) — AArch64: Ada seL4 root task runs under the elfloader in QEMU

**Validated: the full seL4 AArch64 cycle — ELF loader → kernel → Ada root task — boots in QEMU and prints `Hello from Ada (seL4 AArch64 root task)!` (after `Booting all finished, dropped to user space`).**

- `root_task.elf` uses the seL4 AArch64 convention: entry `_sel4_start` @
  `0x400000` (the aarch64-linux-gnu default text segment), corrected from the
  earlier `0x60000000` experiment.
- Injected as the elfloader root server (`strip` → `build/elfloader/rootserver`),
  the CPIO archive is rebuilt, and the cycle prints `sum(1..5) = 0x000000000000000f`.
- seL4 project re-checked-out via `repo` (sel4test-manifest) and built with
  `griddle` (`qemu-arm-virt`, aarch64); `ElfloaderHashInstructions=hash_none`
  lets the pre-built Ada ELF swap in cleanly.

## v1.0.0-pre (2026-10-24) — AArch64: bare-metal Ada runtime validated in QEMU; Ada seL4 root task built

**Validated in QEMU: the Zero-Footprint-Profile runtime (`bare_runtime`) compiles and runs on AArch64 (cross-GNAT 14), printing over the PL011 UART of `qemu-system-aarch64 -M virt` — no hardware, no OS.**

- `arm64/ada/` added: two self-contained artifacts that reuse the x86_64 recipe
  (Ada `--RTS=bare_runtime` + a C shim for the `__gnat_rcheck_*` / libc / unwind
  stubs that the ZFP sources intentionally omit).
- **Artifact 1 (validated):** `hello_world.adb` + `uart.*` + `start.S` +
  `linker_bare.ld` + `runtime_stubs.c` + `build_bare.sh` boot in QEMU and print
  `Hello from Ada (AArch64)!` (sum(1..5) = 0xf).  Proves the bare-metal runtime
  works on ARM64.
- **Artifact 2 (compiled, run pending):** `schild_arm_root_task.adb` +
  `sel4_syscall.*` (seL4 DebugPutChar via `svc #0`) + `root_start.S` +
  `root_linker.ld` + `sel4_stubs.c` + `build_root.sh` produce `root_task.elf`
  (AArch64 ELF, entry `0x60000000`, `svc` present, Ada entry symbol present).
  Booting it under the seL4 elfloader is *pending*: the seL4 project (kernel +
  elfloader via `repo`) is not checked out on this machine.
- `bare_runtime/adainclude/system.ads` is architecture-portable
  (`Standard'Word_Size`), so the x86_64 ZFP runtime needed no change for AArch64.

## v1.0.0-pre (2026-10-24) — ARM64 (AArch64) port: full QEMU cycle works

**Validated in QEMU: the complete seL4 AArch64 stack — ELF loader → kernel → root task — boots and prints `Hello, Schild TCB (ARM64 root task)!`.**

- Toolchain ready: QEMU aarch64, `gcc/g++-aarch64-linux-gnu`, `gnat-aarch64` (Ada cross), `protoc`, `dtc`, `repo`, seL4 Python deps.
- seL4 kernel builds for `qemu-arm-virt` AArch64 (verified 165 KB / debug+printing 148 KB).
- Correct build path is `seL4_tools` (`griddle`) + elfloader + CPIO archive — direct `kernel.elf` boot does not work (no elfloader).
- Minimal C root task (`apps/hello`, `src/schild_core/arm64/apps/hello/`) prints via `seL4_DebugPutChar` (syscall -9) after `Booting all finished, dropped to user space`.
- Direction: Raspberry Pi 4B (BCM2711, `AARCH64_bcm2711_verified.cmake`) — formally-verified AArch64 target (SMP 4 cores, UART debug). No SMMU on RPi — DMA isolation stays out of scope for now.

## v1.0.0-pre (2026-10-24) — CI: full 185-module proof as a manual job; actions bumped to v7

- `prove-full` job added to `.github/workflows/ci.yml`, gated on `workflow_dispatch`
  (manual only): it runs `scripts/prove_kernel.sh` — the complete 185-module
  SPARK Level-4 proof (tens of minutes) — and uploads `obj/proof/report.txt`
  as an artifact. The per-push CI still runs only the fast 7-daemon `verify.sh`.
- `actions/checkout` bumped `@v4 → @v7` (Node 20 → Node 24, removes the runner
  deprecation warning); `actions/upload-artifact@v7` for the report.
- `scripts/prove_kernel.sh` hardened: fails fast if `gnatprove` or the GNAT
  toolchain is missing (mirrors `verify.sh`).

## v1.0.0-pre (2026-10-24) — ARM64 (AArch64) feasibility check (QEMU, prep for Pi 4B)

**Validated in QEMU: the seL4 kernel cross-compiles and starts for AArch64 (`qemu-arm-virt`).**

- Toolchain ready: QEMU aarch64, `gcc-aarch64-linux-gnu`, `gnat-aarch64` (Ada cross), seL4 Python deps.
- seL4 kernel builds for `qemu-arm-virt` AArch64 (verified 165 KB / debug+printing 148 KB) and starts under QEMU.
- Direction: Raspberry Pi 4B (BCM2711, `AARCH64_bcm2711_verified.cmake`) is the formally-verified AArch64 target (SMP 4 cores, UART debug). No SMMU on RPi — DMA isolation stays out of scope for now.
- This is the entry point for the ARM64 port (Phase 0 of the network-gateway roadmap).

## v1.0.0-pre (2026-10-04) — W4: formal proof of the root task (driver Off→On, 7 daemons)

**Validated: `schild_root_task.adb` flipped `SPARK_Mode => Off → On` and proved (54 checks, Level 4); `verify.sh` = 7 daemons, `not-proved: 0`; QEMU 18/18.**

- **Syscall seam contracted:** `schild_sel4_syscall.ads` `SPARK_Mode => On`
  (types `Word`/`Cap_Ref`/`HM_Domain` SPARK-visible); body stays `Off` (seL4
  mechanism). `Put_Hex/Str/Dec` and `Persist_Audit_Log` → `Global => null`.
- **`Schild_Launch_Model` (Level 4):** proves "domain launched exactly once;
  fault endpoints pairwise distinct; shared timeout endpoint bound before first
  launch" — mirrors `Schild_HM_Model`.
- **Driver refactor:** BootInfo read as a VALUE via C shim
  `schild_get_bootinfo_copy` (no opaque access-type deref); `Demo_Shared_Frame`
  moved into the mechanism (its `'Address` is forbidden in SPARK On); root-task
  stack 8→64 KB.
- **The proof caught 2 latent demo bugs** (previously masked by `Off`):
  `Rollback(CD)` with `Mode=Validating` (contract requires `Tentative`), and
  `Wait(Fault_Slot)` with `Fault_Slot=0` on the fallback path — both fixed.
- **Proof gate hardened:** `verify.sh` and `prove_kernel.sh` now fail on any
  `not proved` VC (gnatprove exits 0 even with unproved VCs).

## v1.0.0-pre (2026-10-04) — W5: Fastpath extra-caps bug is non-MCS-specific

**Validated: `KERNEL_FASTPATH=ON KERNEL_MCS=ON` builds (`CONFIG_FASTPATH 1`) and passes 18/18.**

- The documented `excaprefs[0]==NULL → seL4_TruncatedMessage` bug
  (SEL4_INTEGRATION "Known Issue: CONFIG_FASTPATH") **does not reproduce on MCS** —
  it was non-MCS-specific (Stage 6, 2026-08-11). On MCS the fastpath resolves
  extra caps correctly (TCBSetSpace / UntypedRetype / CNodeMint).
- IPC bench is NetServer-dominated (~140k cycles/op): 140182 (ON) vs 140345 (OFF)
  ≈ 0.1%, within noise — it does not isolate the kernel fastpath.
- **Decision:** Fastpath stays an option (`KERNEL_FASTPATH=ON`, default OFF for
  `X64_verified` parity); enable before the network migration (ROADMAP §4).

## v1.0.0-pre (2026-10-04) — W7: NVMe + SchildFS storage isolated in the seL4 NetServer (Ring 3)

**Validated: the NVMe controller and the full SchildFS write-path (Create→Write→Read-verify) run inside the isolated Ring 3 NetServer — QEMU 20/20, `[NVFS] Read-back VERIFY OK`.**

- **Discovery:** `Init_NetServer_NVMe` scans ECAM for the NVMe (144D:A808 /
  1B36:0010 / 8086:5845) with a QEMU fallback @0xfebf0000 (ECAM is already mapped
  by the NIC path, not re-mapped).
- **BAR map:** NVMe BAR0 mapped into the NetServer VSpace at `0x620000`. Fixed the
  shared-device-untyped case (QEMU: NIC + NVMe share one untyped — retype the NVMe
  from the *remaining* untyped `Dev_UT`).
- **Driver:** `C_Addr` now `schild_dma_phys` (queue/PRP addresses get the DMA
  offset in Ring 3); controller setup extracted into `Init_MMIO(MMIO_Base)`;
  `schild_nvme_init`/`schild_nvme_set_mmio` hand the MMIO base root→NetServer.
- **Write-path test** (Net_Nvme_Init): SchildFS Init → Create → Open → Write →
  Read → Verify, printing `[NVFS]` markers.
- bare-metal NVMe `[NVFS]` regression-checked after the refactor.



## v1.0.0-pre (2026-10-04) — W2: seL4 NetServer drives the real I219-V (ECAM + MSI) on T580

**On-hardware validated (ThinkPad T580, I219-V `8086:15d8`): end-to-end TCP/HTTP served from the isolated Ring 3 NetServer.**

- The seL4 NetServer's e1000e was QEMU-hardcoded (`Net_BAR0=0xFEB00000`,
  `GSI=11` PIIX3 INTx). The root task now discovers the real NIC via ECAM
  (MMCONFIG @0xF0000000, mapped as a 2 MiB large page into its VSpace), scans
  bus 0 for the I219-V, reads BAR0 (`0xE8200000`), enables bus-mastering, and
  maps BAR0 into the NetServer VSpace.
- **MSI:** `seL4_IRQControl_GetMSI` + `Program_MSI` (LAPIC `0xFEE00000`,
  vector `0x30`) replaces the QEMU IOAPIC INTx wiring. RX is IRQ-driven via a
  Notification (badge `0xE1`).
- **QEMU fallback preserved:** no ECAM → 82540EM @0xFEB00000, 18/18 markers.
- **Validated on T580:** `[NET] RX IPv4` → `[TCP] ACK → ESTABLISHED` →
  `[HTTP] reply sent` → `[TCP] FIN sent`; a smartphone on the same LAN opened
  the Schild TCB page served by the isolated Ring 3 NetServer over the real
  I219-V (MSI-driven).


## v1.0.0-pre (2026-10-04) — W3: T580 retype hang (root-cause in the root task, not MAX_NUM_DRHU)

**On-hardware validated (ThinkPad T580, 32 GB): `==== Root Task ready ====` — reproduced WITHOUT the MAX_NUM_DRHU patch (re-test 2026-10-24).**

- **Symptom:** the first TCB retype hung in `resetUntypedCap` (memzero) on the
  4 MiB boot-reuse chunk @0x400000 (T580, 32 GB).
- **Root cause (in the root task):** the root task retyped the boot-reuse
  untyped region [1..8 MiB). Fix: `schild_sel4_syscall.adb` filters untyped
  selection to `PAddr >= 16#800000#` (8 sites) — skip BIOS [0..1 MiB) and
  boot-reuse [1..8 MiB), retype only from freemem (≥ 8 MiB).
- **`patches/seL4-max-num-drhu.patch` is an optimization, not the fix:** capping
  `MAX_NUM_DRHU` at 8 shrinks `.boot.bss` (6 MB→5 KB) and `ki_boot_end` 8→2 MiB,
  but the hang does NOT reproduce without it (see seL4/seL4#1790).
- **Validated:** QEMU 18/18; T580 `Root Task ready` with and without the patch.


## v1.0.0-pre (2026-10-04) — seL4-on-T580 boot complete: 32 GB untyped + console speed + TCB retype

**On-hardware validated (ThinkPad T580, 32 GB): full `Root Task ready`.**
- The 32 GB untyped fix (previous entry) is now confirmed on the T580:
  155 untyped caps (77..232), `Total RAM: 32476 MB`, no `Too many untyped regions`,
  no `Slot non-empty` — the earlier blockers are gone.
- **Framebuffer console speed**: the per-character glyph + full-screen scroll on
  the (uncached) GOP framebuffer dominated boot time (~2.5 ms/char, >1 min).
  `schild_fb_putchar` now uses **clear-and-restart** instead of scrolling (one
  write-only clear per screenful, ~2 orders of magnitude cheaper) and 64-bit
  glyph/clear stores. The framebuffer's 1 GiB kernel-window chunk is also mapped
  Write-Combining (PAT[4]) in `patches/seL4-framebuffer-wc.patch`. Boot is now
  effectively instant.
- **TCB UntypedRetype hang**: the first Retype of the 4 MiB boot-reuse untyped
  chunk (0x400000) hung in `resetUntypedCap`'s memzero on the T580 (1 MiB and
  2 MiB chunks were fine). The root task now retypes kernel objects from the
  freemem only — the untyped scan skips `[0..8 MiB)` (`PAddr >= 0x800000`,
  previously `0x100000`) — avoiding the boot-reuse region. 18/18 QEMU markers
  still pass; the T580 reaches `==== Root Task ready ====`.

## v1.0.0-pre (2026-10-04) — 8 KiB boot-info frame + 500 untyped caps (32 GB)

**Validated on T580** (see the entry above).
- The 4 KiB seL4 boot-info frame capped the untyped list at ~244 descriptors;
  the T580's 32 GB RAM + fragmented MMIO produce more, so the kernel warned
  `Too many untyped regions for boot info` and the root task's fixed CSpace
  slots (199..551) landed inside the untyped region (`Slot non-empty`).
- New kernel patch `patches/seL4-bootinfo-8k-untyped.patch`: `seL4_BootInfoFrameBits`
  12→13 (8 KiB), boot-info frame allocated right after the cnode to keep its
  alignment, and `create_bi_frame_cap` maps both pages (first cap →
  `seL4_CapBootInfoFrame`, second via `provide_cap`).
- `KernelMaxNumBootinfoUntypedCaps` 240→500; Ada `N_UNTYPED` 240→500.
- Root-task CSpace slots rebased onto a single `Slot_Base=4096` map in
  `schild_sel4_syscall.ads` (above the max untyped region ~577 = 77+500),
  replacing scattered magic numbers in `schild_sel4_syscall.adb`/`schild_root_task.adb`.
- Verified in QEMU: `run_tests.sh` 18/18 markers; `-m 16G` reaches
  `Root Task ready` with no `Too many`/non-empty errors (Untyped 77..189).
  (*pending:* confirm on T580 — no `Too many untyped regions` + full
  `Root Task ready` at 32 GB.)

## v1.0.0-pre (2026-10-04) — e1000e IRQ-driven RX validated on T580

**On-hardware validation complete (ThinkPad T580, I219-V `8086:15d8`)**
- RX is now genuinely **IRQ-driven with `hlt` idle**: `Run_Loop` halts in `hlt`
  until the e1000e MSI (vector 0x30) fires; `e1000e_irq_handler` sets
  `C_Rx_Pending`, and the loop drains the RX ring on wake. The `cli`/`sti` pair
  around the flag check closes the missed-wakeup race (sti+hlt is atomic on x86).
- Root cause of the earlier "page not rendered" was **TX DMA cache coherence**:
  `Send_Packet` flushed only the first 64-byte cache line of the TX buffer
  (`clflush` is per-line), so frames longer than one line (the ~500-byte HTTP
  response) were DMA-read as stale bytes and dropped by the peer on a bad
  checksum. Fixed by flushing the full buffer range (64-byte steps) before the
  doorbell.
- Server now initiates **TCP FIN** after the HTTP response
  (`Connection: close`): `Initiate_Close` + `FIN_WAIT_1`/`FIN_WAIT_2` states.
- `C_Rx_Pending`/`C_Irq_Count` are marked `pragma Volatile` (imported C globals
  written by the IRQ handler); `irq_count` now increments monotonically in the
  boot log (was stuck at 0 due to compiler caching).
- Verified on T580: `irq_count` 5 → 40 across the session; `[IRQ] e1000e RX`
  wake markers; full HTTP cycle (SYN→SYN-ACK→ESTABLISHED→DATA→ACK, HTTP 200 for
  `/` and 404 for `/favicon.ico`, FIN sent); phone browser renders the page.

## v1.0.0-pre (2026-10-03) — e1000e IRQ-driven RX (standalone kernel)

**Code complete and QEMU-verified; on-hardware RX validation pending**
- The standalone kernel's network RX is now interrupt-driven instead of busy-poll:
  `Schild_Net_Stack.Run_Loop` halts on the RX flag (`e1000e_rx_pending`, set by
  `e1000e_irq_handler` at vector 0x30) and drains the RX ring on wake.
- `schild_kernel_entry.adb` wires the IRQ path (LAPIC enable + C raw IDT with
  vector 0x30 + `sti`) before the network loop. The seL4 build gets link-time
  stubs (`e1000e_rx_pending`/`schild_hlt`); its NetServer never calls `Run_Loop`.
- QEMU boot smoke: `[NET] Stack ready` + `[IDT] Initialized` +
  `[IRQ] e1000e IRQ-driven RX enabled` appear, no panic; 18 seL4 markers PASS;
  `verify.sh` still proved. (*pending:* real-traffic RX on T580.)

## v1.0.0-pre (2026-10-03) — Removed TON/Web3 ledger + Wasm vector

**Dead early-stage vector removed surgically (no build/proof/regression impact)**
- Deleted the standalone ledger/Wasm scaffolds (`schild_distributed_ledger`,
  `schild_ledger_consensus`, `schild_ledger_ipc_gateway`, `schild_ledger_self_test`,
  `schild_wasm_sandbox_interface`) and the `private/userland/` overlay.
- Removed the `ENABLE_DISTRIBUTED_LEDGER` toggle from `build.sh`/`Makefile` and
  the ledger self-test call from `schild_kernel_entry.adb`.
- `private/root_task/` (real Audit/Config/Boot bodies) is unrelated and kept.
- Verified: standalone build 181 objects 0 errors; seL4 18 QEMU markers PASS;
  `verify.sh` 5 modules proved; `prove_kernel.sh` 185 modules `not-proved: 0`.

## v1.0.0-pre (2026-10-03) — Hardware countermeasure state documented (SMEP/SMAP)

**Checked against seL4 boot code (`src/arch/x86/kernel/boot.c`), not inferred**
- CR0.WP: ON (unconditional). SMEP: ON (`CONFIG_DANGEROUS_CODE_INJECTION` off).
  IBRS (Spectre v2): attempted at boot. VT-x: OFF (verified-config default).
- SMAP: **OFF** — seL4 gates SMAP on `!CONFIG_PRINTING`, and the kernel is built
  with `CONFIG_PRINTING=1` (boot logs). Enabling SMAP requires `CONFIG_PRINTING=0`
  (loses logs) or a newer seL4 that decouples them. Documented as residual risk.

## v1.0.0-pre (2026-10-03) — Partition lifecycle + HM escalation formally proved

**ARINC 653 partition lifecycle extracted into provable SPARK (Level 4)**
- New package `Schild_HM_Model` (`tools/sel4/src/schild_hm_model.{ads,adb}`)
  captures the partition lifecycle *decision* logic, separated from the seL4
  *mechanism* (retype / bind / TCBWriteRegisters / TCBResume):
  - `Launch` — one-shot launch (a domain cannot be launched twice);
  - `Evaluate` — fault escalation (process RESTART → partition STOP → module IDLE).
- SPARK contracts: exactly the faulted domain's counter is incremented by one;
  a domain is marked stopped iff its count exceeds `Max_Restarts` (monotonic,
  never un-stopped); **a domain can fault/stop only after it was launched**
  (`Evaluate` Pre requires `Launched`; invariant `stopped ⟹ launched`);
  `Module_Idle` iff all three domains are stopped.
- `verify.gpr` now proves **5 units** (was 4); `scripts/verify.sh` →
  "all verification conditions proved" (`Schild_HM_Model.Launch`: 1 VC,
  `Evaluate`: 5 VCs).
- `Schild_Sel4_Syscall` (`SPARK_Mode => Off`) delegates decisions to the model:
  `Launch_*` record `Launch`, `Health_Monitor` records `Evaluate`. Regression:
  18 QEMU markers PASS (incl. C.8 `MLS server fault -> STOP`).

## v1.0.0-pre (2026-10-03) — seL4 MCS migration (verified in QEMU)

**seL4 root task migrated non-MCS → MCS (`SEL4_PRIMARY=1`, QEMU)**
- MCS kernel rebuilt with `CONFIG_PRINTING=1` (`build_sel4_kernel.sh
  KERNEL_MCS=ON`); `run_tests.sh` passes all 12 markers (MLS, NetServer,
  e1000e IRQ, shared DMA frame, MLS rings, Config Daemon, fault-containment
  badge=0xE2 + HM-restart).
- Syscalls: `Reply` (removed in MCS) → `ReplyRecv` (-2, reply cap in R12);
  `Recv`/`NBRecv` now take a reply object; root task fault/IRQ receive uses
  `Wait` (-9) / `NBWait` (-10) (no reply object). Added `ReplyOnly` (SysSend to
  the reply cap) for the crash-containment "reply then fault" test.
- Thread launch: per-thread `SchedContext` (size_bits=7) + `Reply` object,
  `SchedControl_ConfigureFlags` (budget=period=5000 µs) + `SchedContext_Bind`.
- Fault handler via `TCBSetSpace` MCS (label 11) — fault_ep is resolved in the
  **caller's** CSpace and copied into the TCB (NetServer badged copy 0xE2 is
  minted into root CSpace slot 214, not NetServer's CSpace).
- Invocation label shifts vs non-MCS: TCBSetIPCBuffer 9→10, TCBSetSpace 10→11,
  TCBResume 12→13, CNodeMint 21→22, X86 arch labels +6. Object types: SC=5,
  Reply=6, PDPT 5→7, PML4 6→8, frame 8→10, PT 10→12, PD 11→13.

**Structural cleanup (same commit range)**
- Extracted `Setup_MCS_Thread` (SC+Reply+ConfigureFlags+Bind) shared by the
  three `Launch_*` functions.
- Removed dead non-MCS code: `Send`, `Send_IPC`, `Retype_Notification`,
  `TCB_Configure`, `Info_New` (+ their C/asm counterparts).
- Object types are named constants (`Object_*`) instead of magic numbers.

## v1.0.0-pre (2026-10-03) — MCS temporal isolation + per-domain Health Monitoring

**Per-partition SC budgets (B.5, QEMU)**
- `Setup_MCS_Thread` now takes budget/period (µs) + SC badge; each domain gets a
  distinct round-robin budget: NetServer 5000, MLS 2000, Config 1000 µs.

**Timeout endpoints + fault-injection test (B.6, QEMU)**
- `TCBSetTimeoutEndpoint` (label 9) + shared timeout endpoint @215 + per-domain
  SC badges (NetServer=1/MLS=2/Config=3).
- Config Daemon runs on a sporadic SC (budget=1000µs, period=100ms); `op=98`
  replies then spins to exhaust it. The kernel delivers a `seL4_Fault_Timeout`
  (SC badge in MR[0]); the root task reads badge=3 and reports temporal
  isolation. `run_tests.sh` enforces the `[TIMEOUT]` marker (17 total).

**Health Monitoring for all three domains (C.7, QEMU)**
- `mls_server.c` / `config_daemon.c` gained an op=99 crash-containment path
  (reply then fault on unmapped 0xFFFFF000). The root task now injects a fault
  into MLS (fault ep 199) and Config (fault ep 526) and restarts each via
  `Health_Monitor`.

**3-level ARINC 653 Health Monitoring (C.8, QEMU)**
- `Health_Monitor` tracks per-domain fault counters and escalates:
  process → RESTART (first `Max_Restarts` faults), partition → STOP (repeated
  fault, leave suspended), module → IDLE (all partitions stopped). The root task
  injects the MLS fault twice to demonstrate RESTART then STOP. `run_tests.sh`
  enforces 18 markers.

## v1.0.0-pre (2026-10-03) — Phase E bug fixes (directional mapping + memory map)

**R4 MLS rings ReadOnly right (security-relevant fix)**
- The seL4 X86PageMap rights word uses the CapRights bit layout (bit0=Write,
  bit1=Read), so `seL4_CanRead` = 0x02. The R4 directional mapping used
  `RO := 1`, which the kernel interpreted as *write-only* and masked to
  no-access (x86 has no write-only pages) — the "consumer" pages of the MLS
  rings were inaccessible instead of read-only. Fixed `RO := 2`; the 10×
  `maskVMRights: unsupported write only mapping` warnings are gone.

**Memory map summary**
- The untyped walk stopped at 50 entries (all device), so `Total RAM` printed
  `0 MB`; now walks all `N_UNTYPED` entries (`Total RAM: 490 MB`). Dropped the
  misleading `Total mapped` line (it summed TB-scale reserved device regions).

## v1.0.0-pre (2026-10-03) — IOMMU (VT-d): labels fixed, q35 boots (flaky)

**Kernel side (done).** `build_sel4_kernel.sh` supports `KERNEL_IOMMU=ON`
(`KernelVerificationBuild=OFF`, which the verified config forbids). The
MCS+IOMMU kernel builds and detects VT-d (`ACPI: 1 IOMMUs detected`).

**Label fix (done).** `CONFIG_IOMMU` inserts three extra arch labels
(`X86IOPageTableMap/Unmap`, `X86PageMapIO`) *before* `X86PageMap`, shifting the
later labels: `X86PageMap` 45→47, `X86PageGetAddress` 47→50, `X86ASIDPoolAssign`
49→52, `X86IRQIssueIRQHandlerIOAPIC` 57→60. The C shim now selects `LBL_*`
macros via `-DSCHILD_IOMMU` (plumbed `build.sh`→`build_rt.sh`). Root task passes
all 18 markers under the IOMMU kernel; `run_tests.sh` gained `IOMMU=1`
(`-machine q35 -device intel-iommu`).

**Remaining / known limitation (kernel-level).** Under `KernelVerificationBuild=OFF`
the MCS **sporadic** scheduling-context path hangs non-deterministically
(observed at the Config Daemon's sporadic SC; round-robin SCs are unaffected).
This is an upstream seL4 x86_64 MCS+IOMMU limitation, not a root-task bug. The
actual IO-space/DMA mapping (IOPT + device binding) is still a future step.

**Flakiness isolated (diagnostic).** A root-cause probe confirmed the trigger is
the sporadic *release-period* refill path, not the period magnitude:

| Config Daemon SC (budget/period) | 60s-timeout runs | Result |
|---|---|---|
| round-robin (1000/1000 µs) | 5/5 consistent | boot reaches marker 16; only the B.6 timeout check fails (round-robin never overruns) |
| sporadic 1000/100000 µs (prod) | 4/6 complete | 2/6 hang at Config-Daemon launch |
| sporadic 1000/10000 µs | 2/6 complete | 4/6 hang — smaller period is *worse* |

So the hang is a kernel-level race/timing in the sporadic refill scheduler under
`KernelVerificationBuild=OFF`; there is no period-value workaround (round-robin is
the only stable configuration, but it defeats the B.6 budget-overrun test). The
non-IOMMU kernel (`KernelVerificationBuild=ON`) remains deterministic: sporadic SC
passes all 18 markers. **IOMMU stays experimental/flaky; not a PASS.**

## v1.0.0-pre (2026-08-17) — Phase 3: crash-containment closed (the seL4 story)

**Crash-containment (QEMU, `SEL4_PRIMARY=1`)**
- NetServer TCB fault handler is now an **endpoint** (slot 500, minted badge
  0xE2 into the NetServer CSpace) — non-MCS seL4 `sendFaultIPC` rejects a
  *notification* fault handler as a CapFault ("cap fault in send phase").
- Test flow: the NetServer replies then writes to unmapped `0xFFFFF000`; the
  root task catches the fault with a **blocking `Recv`** on the fault endpoint
  (the NetServer, priority 0, only runs while the root task, priority 255,
  blocks — an NBRecv poll would starve it). Markers
  `[CONTAINMENT] injecting fault…` / `[FAULT] Caught fault` /
  `[CONTAINMENT] core alive after fault` are enforced by `run_tests.sh`.

**Root-task build repairs**
- Three latent defects had made `SEL4_PRIMARY=1` rely on a stale
  `root_task.elf`: undefined `rt_panic` (`message_info.c`), `schild_net_config.o`
  missing from the link, and undefined `schild_log_buf`/`schild_log_len`.

**T580 boot correction**
- `sel4_primary.iso` is a **QEMU artifact**, not a bare-metal image: the seL4
  kernel's Multiboot2 header requests no framebuffer tag, so GRUB prints
  "no console will be available to OS" and the root task's serial log is
  invisible on the T580 (no COM port). The bare-metal artifact is the standalone
  `schild_os.iso` (`boot.S` requests the GOP framebuffer, Multiboot2 tag 5).
  `build.sh` default restored to standalone; `sel4_primary.iso` is built with
  `SEL4_PRIMARY=1`. The sel4_primary grub.cfg now loads `efi_gop`+`gfxmode=auto`.

**Remaining (known)**
- The MLS server (slot 199) and Config Daemon (slot 526) fault handlers are
  still *notifications*; for non-MCS seL4 they must also become endpoints. Not
  exercised because those threads never fault in the current tests.


## v1.0.0-pre (2026-08-16) — SPARK proof closure + honest runtime (ASSURANCE Phases 1-2, 4)

**Phase 1 — closed the proof seams** (`prove_kernel.sh` → `not-proved: 0`, was 5)
- `schild_cap_space`: narrowed `Cap_Index` (0..63) and `Parent_Id`; added the
  `Untyped /= New_Slot` aliasing precondition; rewrote revocation as a provable
  fixpoint with loop invariants.
- `schild_process_manager`: `Find_*` now return a bounded `Slot_Index`; removed
  the dead `goto`.
- `schild_boot_runtime` / `schild_firewall`: replaced hand-rolled `int → string`
  with the provable `Schild_Text.Image`; saturating counters; limiter is now
  self-clamping and `SPARK_Mode => On`.
- `schild_root_task`: added the `Size ≤ Unsigned_32'Last` precondition.
- New tier-B abstractions: `Schild_Log` (`Global => null`) and `Schild_Text`.

**Phase 2 — honest bare-metal runtime**
- Secondary stack is now per-core (xAPIC-ID indexed, 8 KB each, panic on
  overflow) instead of a shared 4 KB wrap-around buffer.
- `system__concat_*` implemented with copy semantics (were no-op garbage).
- `malloc/calloc/realloc` panic loudly instead of silently returning NULL.

**Phase 4 — canonical assurance case**
- `docs/technical/ASSURANCE.md` is the canonical per-component claim: frozen TCB
  (verified vs unverified), verified-claims table, reproducibility commands.
- README aligned: per-component status, dropped the aggregate "high-assurance"
  label, scope markers for `SEL4_PRIMARY` / private-profile items.

## v1.0.0-pre (2026-08-16) — Security hardening (audit findings #1-#7)

**Network stack remote-DoS hardening**
- IPv4 parser now rejects datagrams whose `Total_Len` exceeds the received
  frame length (previously a crafted header claimed up to 65515 payload bytes,
  causing huge stack allocations / out-of-bounds reads and a kernel crash).
- `Parse_Tcp` gained an explicit `Raw'Length >= 20` guard, and the TCP payload
  offset is upper-bounded in the dispatcher, so malformed segments are dropped
  instead of faulting.
- TCP initial sequence number is now generated from RDTSC + a per-boot counter
  (`Generate_Isn`) instead of the fixed `16#DEAD_BEEF#` (predictable-ISN flaw).
- TCP connection table now expires idle connections (~30 s) so a SYN flood
  cannot permanently exhaust the 8 slots.

**Filesystem safety**
- SchildFS moved off LBA 0/1 (protective MBR / primary GPT header) into the GPT
  free gap: `FS_BASE_LBA = 2016`, with a guard that file data cannot grow past
  the first partition (`FS_END_LBA = 2048`).

**Panic → reboot**
- GNAT runtime-check handlers and the C fault/panic handlers now reset the CPU
  via the i8042 controller (0xFE → port 0x64) instead of spinning in `while(1)`,
  so a remotely-triggered fault reboots rather than wedging the kernel.

**Build** — standalone: 177 objects, 0 errors; `verify.sh` (gnatprove Level-4):
  all verification conditions proved; boot tests PASS.

## v1.0.0-pre (2026-08-16) — Stage 11: real-hardware bring-up (ThinkPad T580)

**Observability without a serial port (the T580 has none)**
- The boot log is written to **NVMe LBA 2000** (8 × 512 B blocks) and flushed
  at key boot stages, so the full trace survives a reboot and is readable from
  Linux (`dd if=/dev/nvme0n1 skip=2000 count=16 | strings`).
- NVMe completion status is now decoded from bytes 14-15 (SCT:SC) instead of
  12-13 (CID), so real controller errors are no longer masked as success.

**ECAM PCI enumeration (fixes "NVMe not found" on real hardware)**
- The NVMe SM981 sits on **bus 40 behind a PCIe root port**, and the I219-V
  sits at **00:1f.6 (function 6)**. The legacy 0xCF8/0xCFC mechanism cannot
  reach bus 40, so the scanner now reads the ECAM base from PCIEXBAR
  (00:00.0 offset 0x60; `0xF0000003` → base `0xF0000000`) and uses MMIO
  config access for buses 0..127, with legacy fallback beyond.
- boot.S keeps the identity map at **0-64 MB + 3-4 GB**; the ECAM window
  (0xF0000000) is mapped on demand via the 2 MB MMIO mapper.

**UEFI boot fix (fixes the crash before long mode)**
- Removed the Multiboot2 **EFI boot-services tag (type 7)**: UEFI-GRUB was
  entering the kernel in 64-bit long mode, but boot.S is 32-bit (`.code32`),
  so the first instruction faulted (`#GP` on the `mov %eax, pml4_table`
  moffs). Reproduced in QEMU with OVMF. GRUB now enters in 32-bit protected
  mode as intended; the framebuffer is still passed via tag 8.

**Real hardware validated (ThinkPad T580)**
- Full boot chain confirmed on bare metal: UEFI → 32-bit entry → long mode →
  ECAM → NVMe → framebuffer → seL4 → MLS audit → SchildFS → network stack,
  with the trace readable from NVMe LBA 2000.
- **SMP**: BSP + all 7 APs started on the real i7-8550U.
- **e1000e I219-V**: link up, ARP reply, IPv4, full TCP handshake
  (SYN → SYN-ACK → ESTABLISHED) and HTTP (`GET /` → 200 HTML) served to a
  real client on the LAN.
- Removed a duplicate `Schild_Nvme.Init` inside `Schild_Net_Stack.Init` that
  re-reset the SM981 and hung boot before "Stack ready".
- Throttled the boot-log flush to every 8 packets (per-packet NVMe writes
  dropped RX frames on real hardware).
- **Framebuffer console font fix**: the 8×16 glyph array was corrupted — only
  ~12 of 95 characters had any bitmap data, so on-screen boot text rendered as
  broken/blank glyphs. Replaced it with the complete UNSCII 8-tall font
  (viznut, Public Domain / CC-0, ASCII 32-126); the boot log now renders
  legibly on the GOP framebuffer.
- **Framebuffer console margins**: added 40 px top/left/right margins so boot
  text is no longer clipped by the panel bezel (overscan) at the screen edges.
- **Framebuffer console height + spacing**: boot.S now maps the whole GOP
  framebuffer (it previously mapped a single 2 MB page, capping the console to
  ~13 lines); added 4 px inter-line leading (line height 20 px), and moved the
  framebuffer mirror inside the UART spinlock so concurrent AP-heartbeat writes
  no longer race and overlap into unreadable mush.

**Build** — standalone: 177 objects, 0 errors; seL4 primary: 9/9 PASS;
  boot tests PASS under QEMU SeaBIOS **and** OVMF (UEFI).

## v1.0.0-pre (2026-08-15) — Stage 10: architectural gap closure (audit-driven)

**Correctness fixes**
- Atomic `xchg`-based spinlock (`schild_smp_spinlock`) — replaces the non-atomic
  check-then-set that raced on SMP; `mfence` release ordering.
- Real bitmap frame allocator (`schild_frame_allocator`) — 64 MiB arena
  (16 384 × 4 KiB frames from 2 MiB), replacing the fixed-2 MiB scaffold that
  caused frame aliasing.

**Verified IPC / MLS unification**
- `mls_server.c` now delegates the Bell-LaPadula decision to the verified Ada
  gate `schild_mls_policy.Mls_Authorize_Op` (C-exported) instead of an
  unverified inline C check.
- Removed orphaned scaffolds `schild_ipc_fabric` and `schild_user_ipc`.
- `gnatprove schild_mls_policy`: 0 unproved (11/11 subprograms, 57 checks).

**Real cryptography in the kernel**
- Ported the KAT-validated HMAC-SHA256 (FIPS 180-4 / RFC 2104) into
  `src/03_crypto/schild_hmac_sha256`; removed the zero-digest scaffolds
  `schild_hmac_sha256_gate` and `schild_sha256_core`.
- `gnatprove schild_hmac_sha256`: specification proved (0 unproved); the
  64-round compression body is `SPARK_Mode => Off`, validated by RFC 4231 +
  NIST KATs (not formally proved).

**Network stack — Ethernet/ARP/ICMP/TCP/HTTP confirmed (QEMU socket backend)**
- Fixed **PCI bus-master enable** (missing → the DMA engine could never access
  the TX/RX rings; the earlier "TX confirmed" claim was false — the DD wait
  silently timed out).
- Fixed **TX descriptor layout**: `Cmd`/`Cso` byte offsets were swapped (CMD
  belongs at offset 11, not 10); added 16-byte descriptor-ring alignment,
  reset/EEPROM/link-up waits and the standard TCTL value.
- Fixed **RX tail pointer (RDT)**: was `Idx+1`, which made `RDH==RDT` after the
  first frame and dropped every subsequent packet; now `Idx`.
- Fixed **IPv4 checksum validation**: was comparing the computed checksum to `0`
  instead of to the received checksum field, dropping all IPv4 packets.
- Added an **MMIO read in the poll loop** so QEMU's event loop delivers queued
  socket frames during the otherwise-tight spin.
- Fixed **TCP LISTEN state handling**: the connection initializes to `LISTEN`,
  but `Process_Tcp` only matched `CLOSED`, so an inbound SYN fell through to
  `when others => null` and no SYN-ACK was ever sent. `LISTEN` now accepts the
  SYN identically to `CLOSED`, and `Our_Seq` is advanced past the SYN so later
  segments carry the correct sequence number.
- Fixed **TCP header data-offset decode** (`/256` → `/16`) so option-bearing
  headers are sliced correctly; unified the TCP handler's `Our_IP` with the
  single source of truth in `schild_net_config`.
- Added **inbound TCP checksum validation** over the full segment (header +
  options + payload, with the checksum field zeroed): corrupted segments are
  dropped before any connection-state change, and option-bearing headers from
  real clients validate correctly.
- Fixed **sequence-number accounting**: `Our_Seq` advances past each response
  body, so consecutive requests on one connection carry the correct `Seq_Num`.
- Made the **network poll loop indefinite** (was capped at 5 M iterations, which
  silently stopped serving after ~20 s).
- Fixed **TCP option handling**: the HTTP dispatch required `Data_Off = 0x50`
  and sliced the payload at a hardcoded offset 20, so option-bearing data
  segments (e.g. Chrome's timestamp option) were ACKed but never answered;
  payload is now sliced at the decoded data offset.
- Added a **built-in landing page** for `GET /` (200 + HTML, no filesystem
  required), plus right-aligned `Content-Length` generation.
- Added a **framebuffer console mirror**: every UART log line is now drawn
  to the VBE framebuffer (8x16 font) so the boot log is visible on the
  laptop screen (the T580 has no serial port). The framebuffer is
  initialised first thing in the kernel entry, and its visible height is
  clamped to the single 2 MB huge page boot.S maps (writes past it
  faulted into a triple fault).
- Added **multi-connection support** (8-slot connection table): the single
  global connection previously left the stack stuck after the first close, so
  a second browser request was never answered — the on-hardware
  `ERR_EMPTY_RESPONSE` cause. Verified with two sequential `curl` sessions.
- **Real hardware (ThinkPad T580): Intel I219-V init + link confirmed** — the
  NIC links up on the router and completes the TCP handshake; the HTTP response
  required the option-handling fix above.
- Confirmed with a host-side client over `-netdev socket`: TX broadcast, RX,
  **ARP reply**, **ICMP echo reply**, and the full **TCP handshake + HTTP
  response** (`GET /` → 200 index page, `GET /debug` → 200 + HTML body) all
  work — including option-bearing SYN/data segments (MSS/timestamp) with
  IP/TCP checksums and seq/ack validated on every segment.
- `SCHILD_IP` build-time override for multi-VM testing (single source of truth
  in `schild_net_config`).

## v1.0.0-pre (2026-08-14) — Stage 9.2 / P1 wave 2: hardening (R1, R3, R4, R5, R6, R9)

**Power-loss & hardware-fault detection**
- R1: SchildFS superblock + root-directory CRC32 (torn-write detection) with
  superblock-as-commit-point ordering.
- R5: Config Daemon XOR state checksum (EEC) — bit-flip detection; Validate_Config
  refuses a mismatching state (fail-safe).
- R9: `Persist_Audit_Log` — non-destructive SchildFS snapshot of the audit ring.

**Covert-channel hardening (R4)**
- Per-level MLS SPSC rings (5 split page-pairs @ 0x520000..0x52A000) + directional
  RO/RW mapping (`Page_Map_Rights`); Stage 8.4 shared frame moved to 0x52A000.

**Fault-domain separation (R3)**
- Isolated Config Daemon process (`config_daemon.c` + `Launch_Config_Daemon`);
  full IPC op space verified on boot (MLS read-down/write-up/equal; config allow/deny).

**TCB pruning (R6)**
- `ENABLE_UNWIRED` build flag excludes planned-but-unintegrated modules
  (`iommu/sgx/tme/mmap/net_queue`). Standalone build: **182 → 177 objects, 0 errors**.

## v1.0.0-pre (2026-08-14) — Stage 9.2 / P1 wave 1: verification gap, IRQ coalescing, NVMe timeout, Fastpath benchmark

**SPARK verification gap closed**
- `schild_net_spark_proofs.IPv4_Checksum`: loop-invariant bound corrected from
  `196606` to `589815` (9 words × 0xFFFF). Previously NOT-PROVED (GNATprove found
  counterexample `Sum=196607`); now **proved (5 checks), 0 unproved**.

**e1000e interrupt coalescing**
- `Init_MMIO` programs ITR (`0xC4`) = `0x7D0` (~512 µs) so a packet storm is
  throttled at the source, protecting the control plane from starvation.

**NVMe observable timeout**
- Named `IO_Timeout_Limit` (the 4M-iteration bounded completion poll already
  existed) + `[NVMe] I/O completion timeout` message on hang (observable failure).

**seL4 Fastpath benchmark (verified, KVM)**
- Kernel built twice: Fastpath OFF (186520 B, byte-identical to the prior build)
  and ON (186552 B). IPC Call/Reply round-trip (Root Task → NetServer noop,
  10000 iterations, RDTSCP): **ON 3133 vs OFF 3223 cycles/op** (3 runs each,
  non-overlapping ranges) → **~2.8% faster with Fastpath ON** under KVM
  (VM-exit dominated; larger gain expected on bare metal — pending T580).
- Decision: **default Fastpath OFF** (conservative, parity with the verified
  config); ON available via `KERNEL_FASTPATH=ON`.

## v1.0.0-pre (2026-08-13) — Stage 8.4 + P0 + Stage 9.1: Ring 3 Network, Hardening & Observability

### Status: NetServer (e1000e + TCP/IP) isolated in Ring 3; phase P0 hardening landed

**Syscall & core isolation**
- Dedicated per-process IPC buffer; the seL4 x86_64 ABI is honoured (MR[0..3]
  in registers R10/R8/R9/R15, MR[4+] in the IPC buffer).
- `cteInsert` semantics restored in `invokeTCB_ThreadControl` (MDB correctness);
  deterministic `object-zeroing` removes uninitialized-TCB faults.

**Two-circuit build**
- `SCHILD_PROFILE=public` (scaffold, stub commercial modules) /
  `SCHILD_PROFILE=private` (modules overlaid from `private/`).

**MMIO & memory mapping**
- `Map_NetServer_MMIO`: device-untyped BAR0 → 4K frames → `X86PageTableMap`(37)
  + `X86PageMap`(39) at `0x600000`.

**Asynchronous event wiring**
- Intel e1000e IRQ routed through badged seL4 Notifications (notification@503,
  badged@505 badge `0xE1`, IRQHandler@504).
- **Status:** interrupt routing logic wired through badged seL4 Notifications;
  **pending validation on physical hardware / tap backends** (QEMU slirp
  delivers no interrupts).

**Zero-copy bulk transfer**
- 4 KB shared DMA frame at `0x520000` (frame@506 + mint@507, mapped into both
  VSpaces). Throughput benchmarking is a *target*, not yet measured.

**Formal verification & cryptography**
- HMAC-SHA256 rewritten with a correct multi-block core; **9/9 PASS** against
  RFC 4231 (TC1–TC7) + NIST vectors, wired into CI.
- SPARK Level 4 formal verification of the core MLS policy and the root-task
  daemons via `verify.gpr`, with hardware primitives explicitly marked
  `SPARK_Mode => Off` (excluded from the proved set by design).
- MLS Bell-LaPadula self-tests: **8/8 PASS**.

**Phase P0 (hardening, this sprint)**
- Pruned **194 invalid/duplicate loose modules** (`schild_*.ad[sb]`) from
  `src/schild_core/`; the `src/` build tree is now the single source of truth.
- Wired the verified guard `Schild_Syscall_Arg_Guard.Validate_Syscall_Pointer`
  into `schild_syscall_fabric.adb` (`Dispatch_User_Syscall`): a rejected pointer
  returns `EACCES` (errno 13) in the RAX mirror and aborts dispatch. GNATprove
  re-proved the Post-contract (1 check, 0 warnings, 0 errors).
- Replaced the constant RNG stub (`16#DEAD_BEEF_CAFE_BABE#`) in
  `schild_rng_manager.adb` with real on-CPU hardware entropy
  (`RDRAND`/`RDSEED`), delegating to the asm primitive in
  `schild_random_core.adb`.

**Stage 9 (step 1) — network debug observability**
- `GET /debug` (and `/debug.html`) served from the audit log, never SchildFS.
- Isolated C-bridge: `schild_http_server.adb` `pragma Import`s `schild_debug_render`
  (no-op stub in core `runtime_stubs.c`, keeping 182 objects; the real impl in
  `schild_net_runtime.c` forwards to the Ada export `schild_audit_render` in
  `schild_net_server`, which loops `Buffered_Events` + `Read_Event` and formats
  each `Audit_Event` field). Public profile honestly reports `0 buffered`
  (stub logger); real data flows from the private overlay.

**Verification (this sprint)**
- Standalone build: **182 objects, 0 errors** → `schild_os.elf` 557344 B.
- Root Task: `root_task.elf` 249872 B.

## v0.9.0-pre (2026-08-12) — Stage 8.0: High-Assurance Capability Management

- **TCB lifecycle:** explicit `memzero` during TCB creation; fixed MessageInfo
  evaluation in x86_64 syscall stubs.
- **Compliance mapping (design alignment — not an achieved certification):**
  architecture aligned to Common Criteria (ISO/IEC 15408) EAL6+/EAL7 design
  methodologies and DO-178C Level A objectives; formal MLS Bell-LaPadula policy
  (high-assurance software protection standards).
- **Storage:** bare-metal NVMe 1.4 stack validated (Identify/Read/Write/Verify);
  SchildFS structures.

## v0.8.0-pre (2026-08-10) — Stage 7.0: Symmetric Multiprocessing & Modular Foundations

- **SMP:** BSP + AP cores with inter-processor spinlocks and parallel
  cryptographic workloads (AP-core count pending hardware validation).
- **Layering:** unified abstract interfaces for the modular subsystems,
  isolated from the microkernel core.

---

### Verification snapshot (current)

| Check | Result |
|---|---|
| Standalone build | 177 objects, 0 errors (Ada compiled with `-gnato -gnatVa` runtime checks) |
| SPARK L4 | Core MLS Policy + system contracts verified via verify.gpr; HW primitives `SPARK_Mode => Off` |
| MLS policy (gnatprove) | 11/11 subprograms, 0 unproved |
| HMAC-SHA256 KAT | 9/9 (RFC 4231 + NIST), CI |
| AES-128 KAT | 2/2 (FIPS-197), CI |
| ACPI KAT | 4/4 (RSDP/XSDT/DMAR), CI |
| MLS self-tests | 8/8 |
| seL4 IPC (Root Task → MLS → NetServer) | 0 faults |
| QEMU boot | `==== Root Task ready ====` (seL4) / `[NET] Stack ready` (standalone) |

### Remaining (not yet validated)

- e1000e IRQ-driven RX / tap backend (polling confirmed on QEMU + real I219-V).
- e1000e 82574 validation (I219-V init + link + TCP handshake confirmed on T580;
  HTTP response fixed, pending hardware re-verification).
- IOMMU / PCI-scan + MSI detection (P1).
- Throughput benchmarking of the shared-DMA path.
