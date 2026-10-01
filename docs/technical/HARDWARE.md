# Schild TCB — Hardware map (ThinkPad T580)

## System platform

| Parameter | Value |
|----------|----------|
| **Model** | Lenovo ThinkPad T580 |
| **CPU** | Intel Core i7-8550U @ 1.80 GHz (Kaby Lake R) |
| **Cores** | 4 physical / 8 logical |
| **Cache** | 8 MB L3 |
| **RAM** | 32 GB DDR4 |
| **GPU** | Intel UHD Graphics 620 |
| **Disk** | Samsung NVMe SM981 (970 EVO) |
| **Firmware** | UEFI (no CSM) |

> Boot chain: UEFI-GRUB → Multiboot2 32-bit protected-mode entry (the EFI
> boot-services tag is intentionally absent — boot.S is 32-bit `.code32`) →
> long mode → ECAM → NVMe → framebuffer → seL4 → MLS audit → SchildFS →
> network stack. The boot log is written to NVMe LBA 2000 and survives reboot.

## PCI devices → Schild TCB drivers

| Device | PCI ID | BAR0 (MMIO) | Size | Driver | Status |
|-----------|--------|-------------|--------|---------|--------|
| **Ethernet I219-V** | `8086:15d8` | `0xE8200000` | 128 KB | `schild_e1000e` | ✅ ARP/IPv4/TCP/HTTP end-to-end |
| **UHD Graphics 620** | `8086:5917` | `0xE7000000` | 16 MB | Multiboot2 FB | ✅ Ready |
| **NVMe SM981** | `144d:a808` | `0xE8000000` (bus 40) | 16 KB | NVMe driver | ✅ Init + Write LBA 2000 (ECAM) |
| **WiFi 8265** | `8086:24fd` | — | — | iwlwifi | ⏳ Planned |
| **USB 3.0 xHCI** | `8086:9d2f` | — | — | xHCI driver | ⏳ Planned |
| **Thunderbolt 3** | `8086:15c0` | — | — | Alpine Ridge | ⏳ Planned |
| **HD Audio** | `8086:9d71` | — | — | HDA driver | ⏳ Planned |

## Memory map

```
0x00000000 - 0x04000000  (64 MB)  Identity-mapped (kernel low, 2 MB huge pages)
0xC0000000 - 0xFFFFFFFF  (1 GB)   PDPT[3]: FB + APIC + ECAM + NIC MMIO
  0xE7000000  (16 MB)  GPU Framebuffer
  0xE8200000  (128 KB) Ethernet I219-V
  0xE8000000  (16 KB)  NVMe Controller (bus 40)
  0xF0000000  (128 MB) PCIe ECAM (MMCONFIG; PCIEXBAR@0xF0000000, buses 0..127)
  0xFEE00000  (2 MB)   APIC MMIO
  0xFEB00000  (128 KB) e1000e MMIO (QEMU)
```

## Driver status

| # | Driver | Rationale | Status |
|---|---------|-------------|--------|
| 1 | e1000e (I219-V) | Wired network — critical for a server | ✅ ARP/IPv4/TCP/HTTP end-to-end |
| 2 | NVMe (SM981) | Boot-log + configuration storage | ✅ Init + Write LBA 2000 (ECAM) |
| 3 | xHCI (USB 3.0) | Peripherals | ⏳ Planned |
| 4 | WiFi (8265) | Not critical for a server | ⏳ Planned |
