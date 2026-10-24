#!/usr/bin/env bash
# Build the seL4 microkernel (x86_64, PRINTING=1) and install it as
# tools/sel4/kernel.elf. Reproducible wrapper around the documented recipe.
#
# Env:
#   KERNEL_MCS=ON   -> Mixed Criticality Systems kernel (KernelIsMCS=ON).
#                      Verified: x86_64 (pc99) MCS builds successfully.
#   KERNEL_IOMMU=ON -> VT-d IOMMU support (KernelVerificationBuild=OFF;
#                      the verified config disables IOMMU). EXPERIMENTAL:
#                      the kernel builds and detects VT-d, but the root task
#                      is not yet adapted (KernelVerificationBuild=OFF shifts
#                      ASID/IRQ behaviour; QEMU needs -machine q35, which
#                      moves the PCI/MMIO addresses the root task hardcodes).
#   KERNEL_FASTPATH -> KernelFastpath (default OFF).
#   KERNEL_GFX=linear|none|text -> Multiboot graphics mode (default linear, so
#                      GRUB sets up the T580 framebuffer; `none` keeps the old
#                      no-framebuffer behaviour used by QEMU -nographic).
#   KERNEL_SMP=N    -> number of CPU nodes (KernelMaxNumNodes, default 1).
#                      NOTE: on x86_64, KernelMaxNumNodes DEPENDS on
#                      KernelNumDomains EQUAL 1 — i.e. SMP is NON-MCS only.
#                      With MCS (KernelNumDomains=16) it is forced to 1 (upstream).
#   KERNEL_RESET_CHUNK_BITS=N -> KernelResetChunkBits (default: unset, seL4 default).
#                      For the T580 retype-hang experiment (seL4#1790): try 20.
#   SKIP_DRHU_PATCH=1 -> skip seL4-max-num-drhu.patch (to reproduce the upstream
#                      formula and test whether KernelResetChunkBits alone fixes
#                      the hang — see seL4/seL4#1790).
# Config mirrors docs/technical/CHANGELOG.md: nehalem, PCID=OFF, Fastpath=OFF,
# MaxNumBootinfoUntypedCaps=500 (8 KiB boot-info frame; 32 GB T580), DEBUG_BUILD=OFF.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SEL4_DIR="${SEL4_DIR:-/tmp/seL4}"
PATCH_DIR="$ROOT_DIR/../../patches"

if [ ! -d "$SEL4_DIR/.git" ]; then
  git clone --depth 1 https://github.com/seL4/seL4.git "$SEL4_DIR"
fi

cd "$SEL4_DIR"
git checkout -- . 2>/dev/null || true

if [ ! -d "$PATCH_DIR" ]; then
  echo "ERROR: patches dir not found: $PATCH_DIR" >&2
  exit 1
fi
for p in "$PATCH_DIR"/*.patch; do
  if [ "${SKIP_DRHU_PATCH:-0}" = "1" ] && [[ "$p" == *"max-num-drhu"* ]]; then
    echo "Skipping $(basename "$p") (SKIP_DRHU_PATCH=1) ..."
    continue
  fi
  echo "Applying $(basename "$p") ..."
  patch -p1 < "$p"
done

rm -rf build && mkdir build && cd build

# IOMMU (VT-d): the X64_verified config sets KernelVerificationBuild=ON, which
# disables IOMMU (DEPENDS "NOT KernelVerificationBuild").  Override to OFF so
# CONFIG_IOMMU defaults to ON.  (VT-x stays OFF — its default is OFF.)
IOMMU_FLAG=""
if [ "${KERNEL_IOMMU:-OFF}" = "ON" ]; then
  IOMMU_FLAG="-DKernelVerificationBuild=OFF"
fi

RESET_CHUNK_FLAG=""
if [ -n "${KERNEL_RESET_CHUNK_BITS:-}" ]; then
  RESET_CHUNK_FLAG="-DKernelResetChunkBits=${KERNEL_RESET_CHUNK_BITS}"
fi

cmake -C ../configs/X64_verified.cmake \
  -DKernelX86MicroArch=nehalem \
  -DKernelSupportPCID=OFF \
  -DKernelFastpath="${KERNEL_FASTPATH:-OFF}" \
  -DKernelMaxNumBootinfoUntypedCaps=500 \
  -DKernelIsMCS="${KERNEL_MCS:-OFF}" \
  -DKernelMaxNumNodes="${KERNEL_SMP:-1}" \
  -DKernelMultibootGFXMode="${KERNEL_GFX:-linear}" \
  ${IOMMU_FLAG} \
  ${RESET_CHUNK_FLAG} \
  -G Ninja ..

# Force CONFIG_PRINTING=1 after cmake, before ninja (required for boot logs).
# seL4's generated config disables it as `/* disabled: CONFIG_PRINTING */`.
GEN_CFG=gen_config/kernel/gen_config.h
if [ -f "$GEN_CFG" ]; then
  if grep -q 'disabled: CONFIG_PRINTING' "$GEN_CFG"; then
    sed -i -E 's|/\* disabled: CONFIG_PRINTING \*/|#define CONFIG_PRINTING 1|' "$GEN_CFG"
  else
    sed -i -E 's/#define CONFIG_PRINTING[[:space:]]+[01]/#define CONFIG_PRINTING 1/' "$GEN_CFG"
  fi
  grep -q '#define CONFIG_PRINTING 1' "$GEN_CFG" \
    || { echo "ERROR: failed to enable CONFIG_PRINTING" >&2; exit 1; }
fi

ninja kernel.elf
cp kernel.elf "$ROOT_DIR/tools/sel4/kernel.elf"
echo "Installed kernel.elf -> tools/sel4/kernel.elf"
