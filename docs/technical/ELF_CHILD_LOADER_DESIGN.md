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

> **Практическая сложность (проверено экспериментальной линковкой, round 19):**
> daemon-ELF **не самодостаточен**. `fs_daemon.elf` тянет общий шов: `schild_sel4_ipc.o`
> + `schild_sel4_syscalls.o` + `message_info.o` (syscall), `schild_net_runtime.o`
> (UART/DMA/shared-copy/NVMe-MMIO), `schild_hmac_sha256.o` (H61), `schild_pci_scanner.o`
> (для NVMe). Хуже того, `schild_sel4_ipc.c` ссылается на **все** daemon'ы сразу
> (`mls_server_entry`, `netserver_entry`, `config_daemon_entry` и их `*_cptr`),
> т.е. шов надо **расщепить per-daemon** (или сделать daemon-agnostic), прежде чем
> каждый daemon станет отдельным ELF. Это основная работа шага 4–5.
>
> **Update (round 21–22):** C-шов расщеплён (аксессоры переехали в daemon-`.c`,
> `schild_sel4_ipc.c` стал daemon-agnostic, `08111f4`). Полный набор для
> `fs_daemon.elf` = ~15 объектов: собственные + syscall-шов + `schild_net_runtime`
> + `schild_hmac_sha256` + `schild_pci_scanner` + `schild_audit_logger` +
> `schild_uart_driver` + **стаб `rt_bootinfo_vptr`** (daemon'у boot-info не
> передаётся — `message_info.c` требует символ, нужен `rt_bootinfo_vptr = 0`
> в отдельном daemon-only файле). Стабы собраны в `daemon_stubs.c`
> (`rt_bootinfo_vptr` + `schild_audit_render`).
>
> **Update (round 24):** встройка blob'а в root_task.elf **вызвала boot-loop**
> (root-task image вырос 330→416 КиБ; ядро грузит образ, затем сброс). Встройка
> **откатана** (build_rt.sh), `daemon_stubs.c` + `daemon_linker.ld` оставлены.
> Нужен другой механизм доставки daemon-ELF: отдельный multiboot2-модуль
> (через BootInfo), а не blob внутри root_task.elf.
>
> **Update (round 26, по исходникам ядра):** multiboot2-модуль **тоже не работает** —
> `try_boot_sys_mbi2` записывает только **модуль #0**, `load_boot_module()` вызывается
> **один раз** (root task); доп. модули игнорируются (нет поля BootInfo, extra-регион
> несёт VBE/mmap/ACPI). `build_rt.sh`-линковка `fs_daemon.elf` + `daemon_stubs.c`
> оставлены как готовая инфраструктура.
>
> **Update (round 27, диагностика blob-boot-loop):** причина найдена. Blob (86 КиБ)
> растит образ до 416 КиБ → `mods_end_paddr` сдвигается 0x7a8000→0x799000 —
> **внутрь области ядра** (`ki_p_reg` [0x100000, 0xa21000)). Проверка
> `assert(mods_end_paddr > ki_p_reg.end)` в `boot_sys.c` **выключена** (DEBUG_BUILD=OFF),
> поэтому ядро грузит образ (memzero+elf_load) **поверх собственного boot-кода/данных**
> на 0x799000–0x801000 и уходит в triple-fault (бесконечный reboot; в логе —
> «size=…p_start=0x799000 p_end=0x801000» → «Boot config…» повтор).
> До-blob образ (330 КиБ @ 0x7a8000) попадал в «безвредный» участок, поэтому работал.
> **Фикс blob-пути (round 42, применён):** патч ядра `patches/seL4-load-image-
> above-kernel.patch` — clamp `mods_end_paddr` к `ki_p_reg.end` (release-safe
> замена выключенного assert) + `memcpy` из фактического адреса загрузки
> (`boot_state.ui_info.p_reg.start`). Blob снова встроен в `build_rt.sh`.
> **Проверено: run_tests 23/23** (до фикса — triple-fault).
>
> **Update (round 43, готово):** `Launch_FS_Daemon` переведён на `Load_Elf` —
> читает blob (`schild_fs_daemon_elf_start/size`), грузит в FS VSpace, entry =
> ELF `e_entry`, stack = `fs_daemon_stack_top` (0x417048); +7-й untyped `UT_ELF`.
> FS daemon теперь работает на **своём** ELF (отдельные .text/.data/.bss).
> run_tests 23/23. H87 (FS-daemon) закрыт; остальные daemons — по аналогии.
> **MLS (round 35–39):** `mls_daemon.elf` уже собирается (mls_server + mls_server_c +
> schild_mls_policy + schild_config_daemon + shim + stubs); слот-фикс под рост
> образа применён (§4.1). Встраивание mls-блоба даёт hang Load_Elf: **второй
> `Retype_Object` из того же untyped-капа `0xE9` зависает** (первый retype ок).
> Зацепка: `UT_ELF` = 64 МБ (`Size_Bits=26`), free-index = `MAX_FREE_INDEX` (конец),
> поэтому первый retype через `resetUntypedCap` чистит все 64 МБ; но второй
> (reset=false, без очистки) всё равно виснет — причина не выяснена.
>
> **Update (v0.46, 2026-11-09 — решено):** настоящая причина не во втором
> `Retype_Object`, а в **коллизии mint-копии** в `Load_Segment`: каждая страница
> минтится в `Frame_Slot + 64`. При `MLS_Image_Frame_Base +90` (4186) mint
> давал 4250..4254 → накрывал `Image_Frame_Base` 4224..4354 → `Destination not
> empty` (не hang retype). Фикс: база `+90 → +55` (4151), mint 4215..4219 < 4224.
> Так же `[R3]` target_level 5→4 (0-based). MLS daemon теперь на своём ELF,
> run_tests 24/24.
>
> **Config/NetServer (pending):** `config_daemon.elf` (33 КБ ≈ 9 стр.) и
> `netserver.elf` собираются + блобы встроены, но **Load_Elf-обвязка не сделана**
> — слот-раскладка: mint `+64` требует `Image_Frame_Base < 4160`, а низкие слоты
> `+49..+63` заняты (MLS rings/shared copy/image frames). Нужен либо перенос
> слотов, либо параметризация mint-offset в `Load_Segment`.

Каждый daemon-ELF линкуется со своим linker-скриптом `daemon_linker.ld`
(RX-код, R-rodata, RW-data/bss, entry в `.text` @ 0x400000), затем
**встраивается как ELF-файл** (не `objcopy -O binary` — иначе теряется
ELF-header и `Is_Valid_Header` не пройдёт) в `root_task.elf` как blob:

```sh
# 1. Link the daemon ELF (own linker script, own .o set). .data page-aligned
#    (ALIGN(0x1000)) so small daemons get separate RX/RW PT_LOAD segments.
ld -T src/daemon_linker.ld -o fs_daemon.elf \
   fs_daemon.o fs_daemon_c.o schild_fs_server.o schild_schild_fs.o \
   schild_fs_core.o schild_nvme.o ...

# 2. Embed the ELF FILE (not a flat binary).
ld -r -b binary fs_daemon.elf -o fs_daemon_blob.o
#  → symbols: _binary_obj_root_task_fs_daemon_elf_start / _end

# 3. Link fs_daemon_blob.o into root_task.elf; the root task passes
#    _binary_obj_root_task_fs_daemon_elf_start to Load_Elf (Image_Base) with size.
```

В Ada root task адреса blob'ов импортируются через `Import (C)` на символы
`_binary_*_elf_start`; `Load_Elf` получает `Image_Base` + `Image_Size` + VSpace
даемона + `RAM_UT`/`CNode`/`Slot_Base` и грузит PT_LOAD-сегменты.

> **Slot layout (round 35):** NetServer минтит образ в `Image_Frame_Base+I`
> (4224+), поэтому с ростом образа (blob'ы MLS/Config/NetServer) фреймы
> NetServer'а накрыли `FS_Image_Frame_Base` (4352) → "Slot #4352 non-empty".
> Фикс: `FS_Image_Frame_Base` 4352 → **4480** (`Slot_Base+384`), mint-offset
> `+200` → **`+64`** (иначе mint улетал в MMIO 4608).

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
