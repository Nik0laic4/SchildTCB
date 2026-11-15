# Schild TCB — Final Audit Summary (Assurance Case, Block 4)

**Version:** v0.1 (draft) | **Date:** 2026-11-15
**Scope:** сводка assurance-доказательств по состоянию на конец Блока 3, для финального
Assurance Case (Block 4). Открытые позиции помечены ⏳.

## 1. Доказательства по уровням

| Слой | Доказательство | Статус |
|---|---|---|
| seL4 kernel | upstream proof; 7 локальных патчей (`SEL4_PATCHES_ANALYSIS.md`) — только `object-zeroing` затрагивает доказанный `createObject` | доверен с оговоркой AS8 |
| Ada/SPARK root task | `gnatprove` — MLS политика 0 unproved, `prove_kernel` 180 модулей (0 not-proved) | доказано (уровень 4 для ядра политики) |
| C-шимы (syscall seam) | `SPARK_Mode => Off` — доверенная аксиоматика; `seam-abi` host-KAT + run_tests | доверен + runtime-tested |
| Daemons (H87) | 4/4 на своих ELF (own PML4/CSpace) — FS, MLS, Config, NetServer | ✅ code isolation |
| Bare ring-0 C | `RING0_C_AUDIT.md` — boot.S/IDT/APIC/Rcheck AS8; UART unified; ring-3 driver premature | ✅ аудит |

## 2. Тестовое покрытие (runtime + host)

- `run_tests` **24/24** (seL4, QEMU) — загрузка, MLS, NetServer/FS/Config, containment, fault/timeout.
- host-KAT: `seam-abi` (msgInfo ABI), `elf-kat` (ELF64 parser), `fs-core-kat` (CRC32 + superblock/dir-entry), + существующие (hmac/aes/acpi/ipc/mtf/two_level).
- ⏳ `gnatcov` (Ada coverage) — **не в toolchain** (в `gnat_native` есть только `gcov`), но **есть в локальном индексе Alire** (community: `gnatcov-21.0.1/21.0.2/22.0.1`); установка `alr install gnatcov` блокируется read-only sandbox (`~/.config/alire`, `~/.local/share/alire`).

## 3. Открытые позиции (не блокируют H87, но фиксируются)

| Позиция | Суть | Тир |
|---|---|---|
| C1 ring-3 драйвер | premature: bare-metal без ring-3; seL4 UART уже ring-3 | — |
| root task как ELF-child | убрать DRHU/load-image/bootinfo-8k патчи (L-работа, Блок 3 L) | Tier A |
| gnatcov | в локальном индексе Alire (community); установка блокируется read-only sandbox | — |

## 4. Что осталось до v1.0.0

1. Установить/добыть `gnatcov` (или зафиксировать покрытие как «runtime+host, без gnatcov»).
2. Финальное ревью `TRACEABILITY.md` + `TOOL_QUALIFICATION.md` (sha256 версий инструментов).
3. `RELEASE_NOTES` v1.0.0 + версия в `CHANGELOG`.
