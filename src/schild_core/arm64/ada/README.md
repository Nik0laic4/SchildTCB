# ARM64 Ada root task & bare-metal runtime

This directory is the **Ada/SPARK AArch64** milestone of the ARM64 port. It
holds two self-contained artifacts that (1) prove the Zero-Footprint-Profile
runtime (`bare_runtime`) and the cross-GNAT toolchain work on ARM64, and (2)
provide the seL4 root task written in Ada.

## What is here

| File | Purpose |
|---|---|
| `hello_world.adb` | Bare-metal runtime smoke test (validated in QEMU). |
| `uart.ads` / `uart.adb` | Minimal PL011 driver — spec `SPARK_Mode => On`, MMIO body `Off`. |
| `start.S` | AArch64 entry point for the bare-metal smoke test. |
| `linker_bare.ld` | Bare-metal layout (qemu `-M virt`, load @ `0x40000000`). |
| `runtime_stubs.c` | GNAT runtime stubs for bare metal (report via PL011). |
| `build_bare.sh` | Build + boot the bare-metal smoke test in QEMU. |
| `schild_arm_root_task.adb` | Ada/SPARK seL4 root task. |
| `sel4_syscall.ads` / `.adb` | seL4 debug-console syscall seam (spec `On`; syscall in C). |
| `root_start.S` | seL4 root-task entry point. |
| `root_linker.ld` | seL4 root-task layout (entry `_sel4_start`, load @ `0x400000`). |
| `sel4_stubs.c` | seL4 `svc #0` shim + GNAT runtime stubs. |
| `build_root.sh` | Build the seL4 root task + validate the ELF. |

## Design

The Ada code is compiled against the Zero-Footprint-Profile runtime
`bare_runtime` (`--RTS=.../bare_runtime`) — the same source-only runtime the
x86_64 root task uses.  `bare_runtime/adainclude/system.ads` is architecture-
portable (`Standard'Word_Size`), so no change was needed for AArch64.

GNAT's generated code references a handful of runtime symbols the ZFP sources
deliberately omit (exception/unwind machinery, `memcpy`/`memset`/`memcmp`, and
the `__gnat_rcheck_*` run-time check functions).  These are supplied by a small
C shim (`runtime_stubs.c` / `sel4_stubs.c`) — exactly the approach the x86_64
root task uses (`tools/sel4/src/message_info.c`).  A run-time check failure is a
programming error: the shim reports it and halts the core.

## Artifact 1 — bare-metal runtime (validated)

```bash
./build_bare.sh            # build + boot in qemu-system-aarch64
```

**Validated in QEMU** (`qemu-system-aarch64 -M virt`, PL011 console): the ZFP
runtime compiles and runs on AArch64 without an OS. Output:

```
==== Schild TCB: Ada/SPARK bare-metal runtime (AArch64) ====
Zero-Footprint-Profile runtime + cross-GNAT 14, no OS.
sum(1..5) = 0x000000000000000f
Hello from Ada (AArch64)!
Runtime OK.
```

## Artifact 2 — seL4 root task (validated in QEMU)

```bash
./build_root.sh            # build root_task.elf + validate the ELF
```

The root task prints through `seL4_SysDebugPutChar` (syscall -9, `svc #0`) and
is linked at `0x400000` with entry `_sel4_start` (the seL4 AArch64 convention).
`build_root.sh` validates the ELF: AArch64 machine, entry point, `svc`
instruction, Ada entry symbol.

**Validated:** the full cycle — ELF loader → kernel → Ada root task — boots in
QEMU and prints, after `Booting all finished, dropped to user space`:

```
==== Schild TCB: Ada/SPARK seL4 root task (AArch64) ====
Root task running under seL4 (DebugPutChar via svc #0).
sum(1..5) = 0x000000000000000f
Hello from Ada (seL4 AArch64 root task)!
```

Reproduction (the seL4 project is upstream, fetched with `repo`):

```bash
# 1. seL4 project + kernel/elfloader build (griddle)
mkdir sel4proj && cd sel4proj
repo init -u https://github.com/seL4/sel4test-manifest.git --depth=1
repo sync -j8
mkdir build && cd build
../griddle --PLATFORM=qemu-arm-virt --SIMULATION=ON --KernelSel4Arch=aarch64
ninja

# 2. Build the Ada root task, inject it as the elfloader root server
cd <schild>/src/schild_core/arm64/ada && ./build_root.sh
aarch64-linux-gnu-strip -o <sel4proj>/build/elfloader/rootserver root_task.elf

# 3. Rebuild the elfloader (CPIO + link) and boot the full cycle
cd <sel4proj>/build && ninja
qemu-system-aarch64 -machine virt,gic-version=2 -cpu cortex-a53 -m size=2G \
    -no-reboot -display none -monitor none -serial file:/tmp/serial.log \
    -kernel images/sel4test-driver-image-arm-qemu-arm-virt
cat /tmp/serial.log
```

(`ElfloaderHashInstructions` is `hash_none`, so the pre-built Ada ELF swaps in
without a hash check.)

## Requirements

- `gcc-14` / `gnatmake-14` / `ld` / `readelf` / `objdump` for `aarch64-linux-gnu`
- `qemu-system-aarch64`
- Artifact 2's full cycle: the seL4 project via `repo` (sel4test-manifest) and
  `griddle` (see the reproduction steps above)
