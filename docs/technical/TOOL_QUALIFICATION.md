# Schild TCB — Tool Qualification (Assurance Case, Block 4)

**Version:** v0.1 (draft) | **Date:** 2026-11-15
**Scope:** какие инструменты входят в доверенный вычислительный базис (TCB) и как
они квалифицированы (доказаны / доверены / runtime-tested). Это заготовка финального
Assurance Case; дополняется по мере готовности Блока 4.

## 1. Классификация инструментов

| Инструмент | Роль | Квалификация |
|---|---|---|
| **GNAT Pro compiler** (`gnat_native_14.2.1_06bb3def`) | сборка Ada/SPARK root task + daemons | доверен; код Ada — `SPARK_Mode => On` (доказан gnatprove) |
| **gnatprove** | верификация SPARK (контракты, `not-proved: 0`) | доверен (уровень 4 для ядра политики) |
| **gcc / ld** (`-m64 -ffreestanding -nostdlib`) | C-шимы + линковка | доверен; C-шимы runtime-tested (run_tests 24/24) |
| **seL4 kernel** (7 локальных патчей) | ядро (ring-0), CSpace/VSpace/scheduler | доказан upstream; патчи — `SEL4_PATCHES_ANALYSIS.md` (только `object-zeroing` затрагивает доказанный `createObject`, остальные — boot/MMIO/framebuffer) |
| **mkschildfs.py** | генерация FS-образа | доверен (offline, host) |
| **QEMU** (i440fx, e1000 82540EM) | runtime-валидация | доверен как test-harness (не TCB) |

## 2. Граница TCB (что входит в доверенный базис)

```
ring 0:  seL4 kernel + boot.S + IDT/APIC + GNAT Rcheck (fail-stop) + mmio-map/phys-write
ring 3:  Ada root task (SPARK On где возможно) + 4 daemon ELF (H87, own PML4/CSpace)
         + C-шимы (syscall seam, SPARK_Mode => Off — доверенная аксиоматика)
```

## 3. Замечания по квалификации

- **GNAT** — компилятор не верифицирован формально; доверие переносится на
  **SPARK-контракты + gnatprove** (проверка контрактов, а не корректность кода).
- **seL4 патчи** — 6/7 не затрагивают доказанный код; `object-zeroing` затрагивает
  `createObject` (жизненный цикл объекта, security-relevant) — см. `SEL4_PATCHES_ANALYSIS.md`
  §5/§7. Альтернатива — «root task как ELF-child» (L-работа).
- **C-шимы** — `SPARK_Mode => Off`, доверены как аксиоматика (`SYSCALL_SEAM_ABI_SPEC.md`),
  валидированы runtime (run_tests + host-KAT `seam-abi`/`elf-kat`/`fs-core-kat`).

## 4. Что осталось для финальной версии (Block 4)

- `gnatcov` покрытие (statement/decision) для Ada + `gcov` для C-шимов.
  `gnatcov` есть в локальном индексе Alire (community, до 22.0.1); установка
  `alr install gnatcov` блокируется read-only sandbox (`~/.config/alire`,
  `~/.local/share/alire`) — нужен `danger-full-access` либо fallback «без gnatcov».
- Фиксация **точных версий** инструментов (sha256) в `RELEASE_NOTES` при v1.0.0.
- Ревью каждого пункта §1 перед включением в Assurance Case.
