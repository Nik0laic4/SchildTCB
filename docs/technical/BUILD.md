# Schild TCB — Build instructions

## Dependencies

| Tool | Version | Purpose |
|-----------|--------|-----------|
| GNAT (Ada) | 14.2.1 | Ada/SPARK compiler |
| GCC (C) | 14.2.0 | C compiler |
| AS (GNU) | 2.42 | x86_64 assembler |
| LD (GNU) | 2.42 | Linker |
| gnatprove | 14.1.1 | SPARK verifier |
| grub-mkrescue | 2.12 | ISO image creation |
| qemu-system-x86_64 | 10.0 | Emulation |

## Environment variables

```bash
export TOOL=$HOME/.local/share/alire/toolchains/gnat_native_14.2.1_06bb3def/bin
export RTS=$(pwd)/bare_runtime
export O=obj/development
```

## Build (single command)

```bash
cd src/schild_core
./build.sh
```

Result: ELF ~460 KB, ISO ~23 MB.
175 Ada modules + 6 C + 2 Asm = ~12,500 lines.

## Running QEMU

### Full test (NVMe + e1000e + SMP)
```bash
qemu-system-x86_64 -cdrom schild_os.iso -nographic -m 512M -smp 2 \
  -netdev user,id=net0 -device e1000e,netdev=net0 \
  -drive file=nvme_disk.img,if=none,id=nvme0 \
  -device nvme,serial=SCHILD0001,drive=nvme0
```

### Creating the SchildFS image

`mkschildfs.py` builds the SchildFS structures that live in the GPT free gap
(LBA 2016..2047). See the layout docstring at the top of the script for the
exact A/B superblock / directory / data layout.

```bash
python3 mkschildfs.py schildfs_gap.img

# Write ONLY the gap into the internal NVMe, leaving the protective MBR,
# GPT header and boot-log at LBA 0..2015 untouched:
sudo dd if=schildfs_gap.img of=/dev/nvme0n1 bs=512 seek=2016 conv=notrunc
```

### NVMe tracing (debugging)
```bash
qemu-system-x86_64 ... -trace 'pci_nvme_*' -trace 'nvme_*' 2>trace.log
```

### 2. C (4 files)

```bash
gcc -m64 -nostdlib -nostdinc -fno-builtin -fno-stack-protector \
  -mno-red-zone -ffreestanding -mgeneral-regs-only \
  -c src/runtime_stubs.c src/interrupt_handlers.c \
     src/schild_sel4_boot.c src/schild_sel4_loader.c
```

### 3. ASM

```bash
as --64 -o boot.o boot.S
```

### 4. Link

```bash
gcc -nostdlib -T linker.ld -z noexecstack -z now \
  -o schild_os.elf obj/development/*.o
```

### 5. ISO

```bash
mkdir -p build/iso/boot/grub
cp schild_os.elf build/iso/boot/
grub-mkrescue -o schild_os.iso build/iso
```

## Building seL4

```bash
# 1) Build the seL4 MCS kernel (PRINTING=ON) and install to tools/sel4/kernel.elf
cd src/schild_core
KERNEL_MCS=ON scripts/build_sel4_kernel.sh

# 2) Build the seL4 primary image (MCS kernel + Ada root task → sel4_primary.iso)
SEL4_PRIMARY=1 ./build.sh

# 3) Validate in QEMU (18 markers)
SKIP_BUILD=1 SEL4_PRIMARY=1 ./scripts/run_tests.sh
```

> ⚠️ **Критично при ручной пересборке ядра (не через `build_sel4_kernel.sh`):**
> `DEBUG_BUILD=ON` даёт ядро ~240 КБ, которое **НЕ загружается**; рабочий
> вариант — `DEBUG_BUILD=OFF` + `CONFIG_PRINTING=1` (~186 КБ, загружается).
> Патч «ELF PT_LOAD gap» **ломает** загрузку (`boot_sys.c:452`) — не применять.

## Testing

```bash
# MLS audit (basic)
qemu-system-x86_64 -cdrom schild_os.iso -nographic -m 512M

# With e1000e network (Init + TX test)
qemu-system-x86_64 -cdrom schild_os.iso -nographic -m 512M \
  -netdev user,id=net0 -device e1000e,netdev=net0

# With interrupt debugging
qemu-system-x86_64 -cdrom schild_os.iso -nographic -m 512M \
  -netdev user,id=net0 -device e1000e,netdev=net0 \
  -d int -no-reboot -no-shutdown

# Formal verification
gnatprove -P schild_core.gpr --RTS=$RTS --level=4 \
  -u src/02_security/schild_server_security_policy.adb
```

## Formal verification (SPARK)

### Quick check of critical files
```bash
cd src/schild_core
export PATH="$HOME/.local/share/alire/releases/gnatprove_14.1.1_f6ca6f8c/bin:$HOME/.local/share/alire/toolchains/gnat_native_14.2.1_06bb3def/bin:$PATH"

# Level-4 on a single file
gnatprove -P schild_core.gpr --RTS=bare_runtime --level=4 \
  -u src/01_hardware/schild_timer.ads

# All files with SPARK_Mode => On (Level-2 — fast)
gnatprove -P schild_core.gpr --RTS=bare_runtime --level=2 \
  --mode=flow

# Level-4 on the security domain (slow, ~5-15 min)
gnatprove -P schild_core.gpr --RTS=bare_runtime --level=4 \
  --prover=altergo,cvc5,z3 \
  -u src/02_security/schild_server_security_policy.adb \
  -u src/02_security/schild_process_manager.adb \
  -u src/02_security/schild_signals.adb
```

### Current results (session 2026-08-10)
| File | Level-4 | Status |
|------|---------|--------|
| schild_timer.ads | ✅ | Postcondition proved |
| schild_timer.adb | ✅ | Postcondition proved |
| schild_scheduler.ads | ✅ | Always_Terminates + 2 postconditions + range check |
| schild_scheduler.adb | ✅ | Always_Terminates + 2 postconditions + range check |
| schild_signals.ads | ✅ | Always_Terminates + initializations + postcondition |
| schild_file_descriptors.ads | ✅ | Always_Terminates + initializations |
| schild_sha256_core.ads | ✅ | Overflow check + initialization + postcondition |
| schild_server_security_policy.ads | ✅ | 2 postconditions + 2 Always_Terminates |
| schild_process_manager.ads | ✅ | MLS enforcement proofs (4 postconditions) |

### Strategy for a laptop
1. **Level-2 flow analysis** (~30 sec for the whole project) — data-flow checking
2. **Level-4 on critical files** (~2 sec/file) — mathematical proofs
3. **CI/CD in GitHub Actions** (free, Linux) — full Level-4 run
4. **Incremental verification** — only changed files after git diff

- **SSE/FPU**: enabled in `boot.S` (CR0.TS=0, CR0.EM=0, CR4.OSFXSR=1). Required for Ada code using `pxor`/`movaps`.
- **gnatmake**: glitches possible on repeated runs — `rm -rf obj/development` is recommended.
- **ZFP**: Zero-Footprint Profile (bare_runtime); strings are printed via the C functions `schild_uart_putln`.
- **BSS**: zeroed in `_start` (GRUB2 does not do this).
- **-gnatp**: REMOVED — runtime checks are active.
