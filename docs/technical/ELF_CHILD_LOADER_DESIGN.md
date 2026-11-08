# Schild TCB — ELF Child Loader (H87) — дизайн

**Version:** v0.1 (draft) | **Date:** 2026-11-08
**Статус:** дизайн Блока 3, не реализован. Реализация — 4×Tier A (escalation).

---

## 1. Проблема (H87)

Все daemons (MLS server, NetServer, Config Daemon, FS Daemon) и root task
сейчас слинкованы в **один `root_task.elf`** (см. `tools/sel4/build_rt.sh`
link-list: `schild_mls_policy.o … schild_root_task.o … schild_fs_server.o`).

Каждый daemon имеет **свой PML4 + CSpace** (process-изоляция через seL4), но
**код и данные — общие**: `.text` и `.bss` (RW) отмаплены во все VSpace из
одного ELF-образа.

**Следствие:** OOB-write из скомпрометированного daemon (P2) пишет в общий
`.bss` → повреждает глобальные переменные root task и всех остальных daemons.
Это H87 (shared image RW). RO-image невозможен без ELF loader (`.bss` общий;
каждому процессу нужна своя копия `.bss`, иначе изменения одного видны всем).

## 2. Цель

Каждый daemon — **отдельный ELF-child** со своим `.text`/`.rodata`/`.data`/`.bss`,
загруженным в собственный VSpace. OOB из одного daemon повреждает **только его
собственный** `.bss`, не общий образ. Это же — жёсткая предпосылка для
гипервизорного вектора (DEVELOPMENT_VECTORS §4: «VMM в shared image RW = OOB
в общий .bss», R19).

## 3. Референс (ARM64 net-child)

На ARM64 это уже сделано: `src/schild_core/arm64/ada/sel4_mmio.c` содержит
`vspace_new()` (создание VSpace: VSpaceObject + ASID pool + assign) и
`elf_load_segment()` (retype 4 КиБ-фрейма на каждый `PT_LOAD`, map RX/RW,
копия байт). Маркер успеха: `virtio-net: OK (own VSpace + ELF child)`.

x86_64 повторяет этот паттерн, но для **четырёх** daemons + root task.

## 4. Дизайн (x86_64)

### 4.1 Build-разделение

`build_rt.sh` сейчас линкует все daemon-объекты в один `root_task.elf`. Надо
разделить на отдельные ELF:

| Образ | Содержит |
|---|---|
| `root_task.elf` | root task + seam (`schild_root_task`, `schild_sel4_syscall`, `schild_sel4_bootinfo`, модели HM/Launch) |
| `mls_server.elf` | `mls_server.c` + `schild_mls_policy` |
| `config_daemon.elf` | `config_daemon.c` + `schild_config_daemon` |
| `netserver.elf` | `netserver.c` + `schild_net_server` + `schild_http_server` |
| `fs_daemon.elf` | `fs_daemon.c` + `schild_fs_server` + `schild_schild_fs` + `schild_fs_core` + `schild_nvme` |

Каждый daemon-ELF линкуется со своим linker-скриптом `daemon_linker.ld`
(RX-код, R-rodata, RW-data/bss, entry в `.text` @ 0x400000), затем
конвертируется в flat binary и встраивается в `root_task.elf` как blob:

```sh
# 1. Link the daemon ELF (own linker script, own .o set).
ld -T src/daemon_linker.ld -o fs_daemon.elf \
   fs_daemon.o fs_daemon_c.o schild_fs_server.o schild_schild_fs.o \
   schild_fs_core.o schild_nvme.o ...

# 2. Flatten to a binary.
objcopy -O binary fs_daemon.elf fs_daemon.bin

# 3. Embed the binary into the root task as a symbol.
ld -r -b binary fs_daemon.bin -o fs_daemon_blob.o
#  → symbols: _binary_fs_daemon_bin_start / _end / _size

# 4. Link fs_daemon_blob.o into root_task.elf; the root task passes
#    _binary_fs_daemon_bin_start to Load_Elf (Image_Base) with _size.
```

В Ada root task адреса blob'ов импортируются через `Import (C)` на символы
`_binary_*_bin_start`; `Load_Elf` получает `Image_Base` + `Image_Size` + VSpace
даемона + `RAM_UT`/`CNode`/`Slot_Base` и грузит PT_LOAD-сегменты.

### 4.2 ELF loader (memory-safe, в TCB)

Новая единица в root task (Tier A, `SPARK_Mode => On` где возможно):

- Парсинг ELF-header: magic `\x7fELF`, class/endianness, program headers.
- Для каждого `PT_LOAD`: retype фреймов → map в daemon VSpace (RX для code,
  RW для data/bss) → копия байт → обнуление `.bss`.
- **Каждое поле header ограничено проверками** (нет доверия к метаданным ELF:
  число phdr, смещения, размеры — всё против границ образа).
- Документируется как **trusted** (это часть TCB: он маппит код в VSpace).

### 4.3 Launch-изменения (4 × Tier A)

| Файл | Изменение |
|---|---|
| `schild_sel4_syscall.adb` | `Launch_MLS_Server`/`Launch_NetServer`/`Launch_Config_Daemon`/`Launch_FS_Daemon` — вместо общего образа грузят свой ELF через loader |
| `schild_root_task.adb` | передаёт адрес/размер каждого daemon-ELF в Launch_* |
| `schild_boot_manager.adb` | (если он учитывает образы) — список образов daemon |
| `schild_launch_model.adb` | модель запуска обновлена: ELF-child, не shared-image |

### 4.4 Shared DMA frame

Shared frame @`0x52A000` остаётся общим по явному решению (root/NetServer/FS,
сериализовано однопоточным root task — H92). Это НЕ `.bss`, поэтому H87 его не
затрагивает.

## 5. Escalation и гейты

- 4 × Tier A файла (allowlist): правки требуют escalation + diff Pre/Post +
  `not-proved: 0` + 5 гейтов перед коммитом.
- `schild_fs_core` (SPARK On) остаётся доказанным; loader — отдельный proof-unit
  с контрактами на границы ELF-метаданных.

## 6. Residuals

- Loader — trusted (memory-safe + документирован), как ARM64-аналог.
- Пока RDRAND-ключ (H61) детерминирован: линковка `Schild_Rng_Manager` сдвигала
  общий ELF (H87 size-sensitivity) — с раздельными ELF эта чувствительность уходит.

## 7. Out of scope

- SMP x86_64 MCS, IOMMU/VT-d — upstream (см. ROADMAP §4, W6).
