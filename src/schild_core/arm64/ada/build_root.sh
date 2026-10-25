#!/usr/bin/env bash
# =============================================================================
# Schild TCB -- build the Ada/SPARK seL4 root task for AArch64.
#
# Compiles schild_arm_root_task.adb against --RTS=bare_runtime, links it with
# the seL4 SVC shim (sel4_stubs.c) and the root-task entry (root_start.S) into
# root_task.elf, and validates the resulting ELF (machine, entry point, syscall
# instruction).  The QEMU run under the seL4 elfloader is *not* performed here
# because the seL4 project (kernel + elfloader) is not checked out on this
# machine -- see arm64/README.md.
#
# Usage:
#   ./build_root.sh
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

RTS="$(cd ../../bare_runtime && pwd)"
PREFIX="${CROSS:-aarch64-linux-gnu-}"

GNATMAKE="${PREFIX}gnatmake-14"
GCC="${PREFIX}gcc-14"
LD="${PREFIX}ld"
READELF="${PREFIX}readelf"
OBJDUMP="${PREFIX}objdump"

for tool in "$GNATMAKE" "$GCC" "$LD" "$READELF" "$OBJDUMP"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "[root] ERROR: tool not found: $tool" >&2
        exit 1
    fi
done

rm -rf obj obj_child && mkdir -p obj obj_child

# 1. Compile the Ada closure (root task + Sel4_Syscall + needed runtime units).
"$GNATMAKE" -c --RTS="$RTS" -gnat2022 -gnatwa -O0 -g \
    -fno-pie -fno-pic -I. -D obj schild_arm_root_task.adb

# 2. Assemble the entry point.
"$GCC" -c -fno-pie -fno-pic -o obj/root_start.o root_start.S

# 3. Compile the seL4 shims (DebugPutChar syscall + GNAT runtime stubs),
#    the platform/MMIO layer + virtio-net driver, and the protocol test.
"$GCC" -c -ffreestanding -nostdlib -nostdinc -fno-builtin \
    -fno-pie -fno-pic -fno-stack-protector -O2 \
    -o obj/sel4_stubs.o sel4_stubs.c
"$GCC" -c -ffreestanding -nostdlib -nostdinc -fno-builtin \
    -fno-pie -fno-pic -fno-stack-protector -O2 \
    -o obj/sel4_mmio.o sel4_mmio.c
"$GCC" -c -ffreestanding -nostdlib -nostdinc -fno-builtin \
    -fno-pie -fno-pic -fno-stack-protector -O2 \
    -o obj/net_test.o net_test.c

# 4. Build the child process ELF: the net driver + protocol, compiled from the
#    same sources into a separate image and embedded as a raw blob so the root
#    task can load it into the child's own VSpace at boot.  --gc-sections drops
#    the root-only platform code (BootInfo/MMIO-map/child-spawn/VSpace loader),
#    leaving only the driver + protocol + syscall shims the child needs.
"$GCC" -c -ffreestanding -nostdlib -nostdinc -fno-builtin \
    -fno-pie -fno-pic -fno-stack-protector -O2 \
    -ffunction-sections -fdata-sections \
    -o obj_child/sel4_mmio.o sel4_mmio.c
"$GCC" -c -ffreestanding -nostdlib -nostdinc -fno-builtin \
    -fno-pie -fno-pic -fno-stack-protector -O2 \
    -ffunction-sections -fdata-sections \
    -o obj_child/net_test.o net_test.c
"$GCC" -c -ffreestanding -nostdlib -nostdinc -fno-builtin \
    -fno-pie -fno-pic -fno-stack-protector -O2 \
    -ffunction-sections -fdata-sections \
    -o obj_child/sel4_stubs.o sel4_stubs.c
"$GCC" -c -fno-pie -fno-pic -o obj_child/child_start.o child_start.S
"$LD" --gc-sections -T child_linker.ld -o obj_child/child.elf \
    obj_child/child_start.o obj_child/sel4_mmio.o obj_child/net_test.o obj_child/sel4_stubs.o

echo "[root] child.elf: $(wc -c < obj_child/child.elf) bytes"
LC_ALL=C "$READELF" -h obj_child/child.elf | grep -E 'Type:|Machine:|Entry point'

# Embed obj_child/child.elf into the root ELF (.incbin with explicit symbols).
printf '.section .rodata\n.balign 8\n.globl child_elf_start\n.globl child_elf_end\nchild_elf_start:\n.incbin "%s/obj_child/child.elf"\nchild_elf_end:\n' \
    "$(pwd)" > obj/child_elf.S
"$GCC" -c -fno-pie -fno-pic -o obj/child_elf.o obj/child_elf.S

# 5. Link: root_start.o first (it owns _start), then the rest of the closure.
mapfile -t OBJS < <(find obj -name '*.o' ! -name 'root_start.o' | sort)
"$LD" -T root_linker.ld -o root_task.elf obj/root_start.o "${OBJS[@]}"

echo "[root] root_task.elf: $(wc -c < root_task.elf) bytes"
echo "[root] --- ELF validation ---"
LC_ALL=C "$READELF" -h root_task.elf | grep -E 'Class:|Type:|Machine:|Entry point'

# grep -c reads the whole stream (no SIGPIPE early-exit), which is required
# under `set -o pipefail` (a -q early-exit would signal a false failure).
SVC_COUNT=$(LC_ALL=C "$OBJDUMP" -d root_task.elf | grep -c 'svc' || true)
if [ "$SVC_COUNT" -gt 0 ]; then
    echo "[root] syscall instruction (svc #0): present ($SVC_COUNT sites)"
else
    echo "[root] ERROR: no svc instruction found" >&2
    exit 1
fi

ENTRY_SYM=$("$PREFIX"nm root_task.elf | grep -c '_sel4_start' || true)
if [ "$ENTRY_SYM" -gt 0 ]; then
    echo "[root] seL4 entry (_sel4_start): present"
else
    echo "[root] ERROR: seL4 entry symbol missing" >&2
    exit 1
fi

ADA_SYM=$("$PREFIX"nm root_task.elf | grep -c '_ada_schild_arm_root_task' || true)
if [ "$ADA_SYM" -gt 0 ]; then
    echo "[root] Ada entry (_ada_schild_arm_root_task): present"
else
    echo "[root] ERROR: Ada entry symbol missing" >&2
    exit 1
fi
