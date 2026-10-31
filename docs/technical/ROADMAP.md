# Schild TCB — Дорожная карта (ROADMAP)

**Version:** v1.2  |  **Date:** 2026-10-31
**Developer:** Ирганов А.Н.
**Status:** каноничный единый источник истины о «что дальше».

> Этот файл **заменяет** разрозненные секции «remaining work» из
> `ASSURANCE.md` (§5–6), `ARCHITECTURE.md` (§11),
> `PROJECT_PASSPORT.md` (§9). Все ссылки на «что дальше» должны вести сюда.
> **Правило:** каждое утверждение указывает на модуль + механическую проверку;
> никаких агрегатных «high-assurance» без per-component указателя.

---

## 1. Текущее валидированное состояние (2026-10-31, HEAD `a027f5c`)

| Компонент | Статус | Механическая проверка |
|---|---|---|
| Bare-metal ядро — сборка | ✅ 0 ошибок | `./build.sh` |
| Bare-metal ядро — SPARK L4 | ✅ `not-proved: 0` | `scripts/prove_kernel.sh` → `obj/proof/report.txt` (185 модулей; `~108 proved / ~77 out-of-proof`) |
| Демоны root-задачи — SPARK L4 | ✅ все VC доказаны | `scripts/verify.sh` (`verify.gpr`, 7 модулей) |
| Модель угроз | ✅ | `docs/technical/THREAT_MODEL.md` |
| Контрактный аудит (Tier-A) | ✅ усилены, `not-proved: 0` | `docs/technical/SESSION_CONTRACT_AUDIT.md` |
| Boot counter (A/B + порог блокировки) | ✅ доказано | `scripts/verify.sh` (`schild_boot_manager` 8 подпрограмм); `BOOT_COUNTER_DESIGN.md` |
| Health check перед commit (W9.2) | ✅ доказано | `scripts/verify.sh` (`Commit_If_Healthy`, `schild_boot_manager` 10 подпрограмм) |
| Watchdog (W9.3, логика kick/expire) + Load/Save round-trip | ✅ логика доказана | `scripts/verify.sh` (`schild_watchdog` 5; `To_Persistent`/`From_Persistent`); таймер/NVMe-упаковка deferred |
| Bare-metal boot + сеть | ✅ T580 + QEMU | `run_tests.sh` (`SEL4_PRIMARY=0`); HTTP на T580 (IRQ-driven RX) |
| seL4 ветка — сборка | ✅ | `SEL4_PRIMARY=1 ./build.sh` |
| seL4 ветка — QEMU | ✅ 20/20 маркеров | `run_tests.sh` (`SEL4_PRIMARY=1`) |
| seL4 ветка — T580 (32 ГБ) | ✅ `Root Task ready` | прошивка `sel4_primary.iso` → T580 |
| seL4 MCS | ✅ QEMU-валидирован | `MCS_MIGRATION.md` |
| IOMMU (VT-d) | ⛔ experimental/flaky | upstream sporadic SC race (x86_64 MCS) |
| SMEP / CR0.WP | ✅ ON | ядро seL4, boot |
| SMAP | ✅ ON | `seL4-smap.patch` (включён вместе с `CONFIG_PRINTING`) |

---

## 2. Ключевой архитектурный факт (почему следующий шаг именно этот)

`Root Task ready` на T580 = **загрузка + containment + временная изоляция** на
железе. Это **НЕ** сетевая изоляция: сетевой путь seL4-NetServer захардкожен
под QEMU —

- `schild_sel4_syscall.adb:598` → `Net_BAR0 := 16#FEB00000#` (QEMU 82540EM);
- `schild_sel4_syscall.adb:933-941` → `Net_GSI = 11` (i440fx PIIX3 IOAPIC INTx).

Реальная I219-V (`8086:15d8`) на T580 работает по ECAM-скану + MSI (реализовано
в **bare-metal** ядре: `schild_pci_scanner.adb`, `schild_msi_allocator.adb`,
`schild_e1000e.adb`), но в seL4-NetServer ещё **не перенесено**. Маркеры
`[S8.3]`/`[S8.4]` на T580 проходят **вакуумно** (grep видит строку, реальная NIC
не задействована).

---

## 3. Порядок работ (стабильность и чистота — приоритет)

### W1 — Гигиена документации (закрывается этой сессией)

- Введён этот каноничный ROADMAP.
- Исправлены **вводящие в заблуждение** утверждения:
  - `PROJECT_PASSPORT.md` §2 («`sel4_primary.iso` только QEMU, не для T580»)
    → обновлено (seL4 грузится на T580 32 ГБ с 2026-10-04);
  - `ASSURANCE.md` §3 («`prove_kernel.sh` currently reports `not-proved: 5`»)
    → помечено как историческое (закрыто в Phase 1).
- ✅ Счётчики модулей выровнены (W4-сессия): README/PASSPORT приведены к
  каноничным **185** (~108 proved + ~77 skipped/out-of-proof). Каноничный
  счётчик — `prove_kernel.sh` → `obj/proof/report.txt`; хардкодить число в
  доках не следует.

### W2 — Реальная сетевая изоляция на T580 (✅ закрыт, T580 валидирован)

Порт драйвера e1000e (ECAM-скан + MSI + I219-V) из bare-metal в seL4-NetServer:

1. ✅ Root-задача обнаруживает I219-V через ECAM (вместо `0xFEB00000`).
2. ✅ Retype + map настоящего BAR0 (`0xE8200000`) в VSpace NetServer.
3. ✅ MSI: `GetMSI` + `Program_MSI` (вместо `GSI=11`/IOAPIC INTx).
4. ✅ Реальный трафик: `[TCP] ACK → ESTABLISHED` → `[HTTP] reply sent` → `FIN`.

**Валидировано на T580:** сеL4-NetServer (изолированный Ring 3) раздаёт HTTP
через реальную I219-V (MSI-driven, IRQ-RX badge `0xE1`); смартфон в той же LAN
открыл страницу. QEMU-фолбэк (82540EM) — 18/18.

**Exit (выполнен):** seL4-NetServer раздаёт реальный HTTP с I219-V на T580.

### W3 — Зависание memzero `@0x400000` (✅ закрыт; root-cause в root-задаче, не в MAX_NUM_DRHU)

**Симптом (2026-10-04):** первый retype виснет в `resetUntypedCap` (memzero) на
4-МиБ boot-reuse куске `@0x400000` (T580, 32 ГБ).

**Root cause (в root-задаче):** root-задача ретайпила boot-reuse регион
`[1..8 МиБ)`. Обход: `schild_sel4_syscall.adb` фильтрует выбор untyped —
`PAddr >= 16#800000#` (8 мест) — пропускает BIOS `[0..1 МиБ)` и boot-reuse
`[1..8 МиБ)`, ретайпит только из freemem (≥ 8 МиБ).

**`patches/seL4-max-num-drhu.patch` — оптимизация, не фикс:** cap
`MAX_NUM_DRHU := 8` уменьшает `.boot.bss` (6 МБ→5 КБ) и `ki_boot_end` 8→2 МиБ,
но ханг **не воспроизводится и без патча** (re-test 2026-10-24, `seL4/seL4#1790`).

**Валидировано:** QEMU 18/18 + T580 (32 ГБ) → `==== Root Task ready ====`
с патчем и без, `Total RAM: 32476 MB`.

**Exit (выполнен):** T580 доходит до `==== Root Task ready ====` без зависания.

### W4 — Формальное доказательство root-задачи (расширение Tier A) ✅ ЗАКРЫТ

**Итог:** root-задача (`schild_root_task.adb`) переведена `SPARK_Mode => Off → On`
и доказана (54 checks, Level 4); сшив `Schild_Sel4_Syscall` законтрактован
(spec On, тело Off); в `verify.gpr` доказаны 7 демонов (MLS, Config, Audit, Boot,
HM Model, Launch Model, Root Task). HW-драйверы не тронуты.

1. ✅ Законтрактовать syscall-шов `Schild_Sel4_Syscall`: спецификация переведена
   `SPARK_Mode => Off → On` — типы (`Word`/`Cap_Ref`/`HM_Domain`) стали
   SPARK-видимыми, 12 high-level операций получили `Global => null`; тело остаётся
   `Off` (seL4-механизм retype/map/MMIO/MSI — доверенная аксиоматика, не
   доказывается). `Put_Hex/Put_Str/Put_Dec` (`Schild_Sel4_BootInfo`) — `Global =>
   null`, вызываемы из On-кода.
2. ✅ Вынесены `Launch_*`-последовательности (MLS/NetServer/Config) в SPARK-пакет
   `Schild_Launch_Model` (по образцу `Schild_HM_Model`, Level 4) и вшиты в
   механизм: `Bind_Timeout_EP` в `Init_Fault_Handler`, `Launch` для каждой
   партиции в `Launch_MLS_Server` / `Launch_NetServer` / `Launch_Config_Daemon`.
3. ✅ Доказан инвариант «домен запущен ровно один раз; fault-эндпоинты попарно
   различны; timeout-эндпоинт связан до первого запуска» (`Valid_State`, L4).
4. ✅ Перевести `schild_root_task.adb` `Off → On` — **выполнено, доказано
   (54 checks, Level 4)**. Блокеры решены: (a) `Get_BootInfo` access-тип →
   value-copy C-шимм `schild_get_bootinfo_copy` (`message_info.c`) +
   `Get_BootInfo_Copy`; (b) `Frame'Address` в demo shared-frame → вынесено в
   `Demo_Shared_Frame` (механизм, Off-тело); (c) `RDTSC` — `Global => null`;
   (d) `Persist_Audit_Log` — `Global => null` (вызываем из On). Доказательство
   вскрыло и 2 реальных латентных бага демо: `Rollback` при `Mode=Validating`
   (контракт требует `Tentative`) и `Wait(Fault_Slot)` при `Fault_Slot=0`
   (фолбэк-путь) — исправлены. Стек root-задачи 8→64 КБ (value-копия BootInfo
   ~8 КБ).

**Гейт (усилен, W4-сессия):** `verify.sh` и `prove_kernel.sh` теперь падают при
любом `not proved` (gnatprove возвращает 0 даже при непроверенных VC — источник
истины отчёт `obj/*/gnatprove/gnatprove.out`, а не exit-код).

**Exit:** `verify.sh` покрывает оркестрационный слой (7 демонов: MLS, Config,
Audit, Boot, HM Model, Launch Model, **Root Task**), `not-proved: 0`;
`run_tests.sh` 18/18 без регрессий — **W4 закрыт полностью**.

### W5 — Fastpath + баг extra-caps (✅ resolved: non-MCS-specific)

**Итог (W5-сессия):** `KERNEL_FASTPATH=ON KERNEL_MCS=ON` собирается
(`CONFIG_FASTPATH 1`) и проходит **18/18** — баг `excaprefs[0]==NULL →
seL4_TruncatedMessage` **не воспроизводится на MCS**. Баг был специфичен для
non-MCS (Stage 6, 2026-08-11); на MCS fastpath корректно резолвит extra-caps
(TCBSetSpace / UntypedRetype / CNodeMint — 18/18).

Benchmark: `cycles_per_op` 140182 (ON) vs 140345 (OFF) — ≈0.1%, в пределах шума:
текущий bench меряет полный round-trip через Ring-3 NetServer (~140k циклов),
он не изолирует ядерный fastpath (CHANGELOG'овские ~2.8% — raw-IPC под KVM).

**Решение:** Fastpath остаётся опцией (`KERNEL_FASTPATH=ON`, default OFF —
parity с X64_verified). Включать перед переносом сети (ROADMAP §4); на MCS
никакого фикса не требуется.


### W6 — SMP: перенос bare-metal SMP в seL4 (⛔ upstream: MCS+SMP не поддерживается)

**Итог (W6-сессия):** на x86_64 `KernelMaxNumNodes` имеет `DEPENDS
"KernelNumDomains EQUAL 1"` (`config.cmake:151`). С MCS (`KernelNumDomains=16`)
опция форсится в 1 (`KernelMaxNumNodes_UNAVAILABLE=ON`) — **MCS + SMP на x86_64
не поддерживается upstream** (так же, как IOMMU). `KERNEL_SMP=8` собирается, но
ядро остаётся одноядерным (`CONFIG_MAX_NUM_NODES 1`).

**Вывод:** миграционная последовательность §4 — сеть ✅ → IOMMU ⛔ → SMP ⛔ →
хранилище. Оба «аппаратных» шага (IOMMU, SMP) заблокированы upstream для MCS
x86_64; bare-metal SMP остаётся validation oracle до parity. Следующий
действующий шаг — **хранилище (NVMe/SchildFS parity в seL4)** или мониторинг
upstream-фиксов IOMMU/SMP. `KERNEL_SMP` оставлен в `build_sel4_kernel.sh` как
документация (работает только на non-MCS).


### W7 — Хранилище: NVMe/SchildFS в seL4 NetServer ✅ ЗАКРЫТ

**Итог (W7-сессия):** NVMe + SchildFS полностью перенесены в seL4 NetServer
(Ring 3) и валидированы. Полная цепочка:

1. ✅ `Init_NetServer_NVMe` — ECAM-скан NVMe (144D:A808 / 1B36:0010 / 8086:5845) +
   QEMU-фолбэк `0xfebf0000` (ECAM уже замаплен NIC-путём, не пере-вызывается).
2. ✅ BAR-map: NVMe BAR0 → `0x620000`; **shared-untyped fix** — на QEMU NIC и NVMe
   в одном device-untyped, NVMe retype'ится из остатка `Dev_UT` (offset от
   `UT_PAddr + Total_Frames*0x1000`).
3. ✅ Драйвер: `C_Addr → schild_dma_phys` (DMA-фикс), `Init_MMIO(MMIO_Base)`
   вынесен, `schild_nvme_init`/`schild_nvme_set_mmio` — handoff root→NetServer.
4. ✅ Тест: SchildFS write-path в NetServer — `[NVFS] Mounted OK → File created →
   Write OK → Read-back VERIFY OK` (Create→Open→Write→Read→Verify).

**Exit (выполнен):** NVMe инициализируется в seL4; SchildFS write-path
валидирован в NetServer (`[NVFS] Read-back VERIFY OK` в `SEL4_PRIMARY=1`);
QEMU **20/20**; bare-metal `[NVFS]` без регрессий.


### W8 — Контрактный аудит + модель угроз ✅ ЗАКРЫТ (2026-10-31)

**Итог (W8-сессия):** модель угроз (`THREAT_MODEL.md`) + усиление контрактов
security-критичных модулей (cap_space, process_manager, signals, mls, ipc).
Детали и остатки — `SESSION_CONTRACT_AUDIT.md`. Полный proof: `not-proved: 0`,
`~108 proved / ~77 out-of-proof`.

### W9 — Фаза надёжности (boot/update/recovery) — `[в работе]`

1. **Boot counter** ✅ ЗАКРЫТ (2026-10-31) — логика A/B + порог блокировки
   (`Max_Boot_Attempts = 3`), `Slot_Locked`/`Is_Bricked`, brick-состояние;
   энергонезависимое хранилище зафиксировано (`BOOT_COUNTER_DESIGN.md`:
   NVMe LBA 2048 + HMAC-тег, x86 CMOS fallback). Доказано `verify.sh`
   (`not-proved: 0`, `schild_boot_manager` 8 подпрограмм).
2. **Health check перед commit** ✅ ЗАКРЫТ (2026-10-31) — `Health_Status`
   (сеть + MLS), `Health_Ok`, `Commit_If_Healthy` (commit iff healthy, else
   failover); self-test `[S7] T6a/T6b`. Доказано `verify.sh`
   (`schild_boot_manager` 10 подпрограмм, `not-proved: 0`).
3. **Watchdog** ✅ логика (2026-10-31) — `schild_watchdog` (kick/expire),
   self-test `[S7] T7a/T7b`; доказано `verify.sh` (5 подпрограмм). Хардварный
   таймер (PIT/APIC, BCM2711) — deferred (⚠️ железо).
4. **Tryboot / Rescue slot** — конфиг bootloader (❌ Pi 4).

**Безжелезные долги закрыты (2026-10-31):** Load/Save round-trip
(`To_Persistent`/`From_Persistent`) ✅; `schild_boot_runtime` `Refined_State` ✅;
`Is_Derived_From` (cap_space) ✅. Осталось только железо (таймер, NVMe-упаковка,
bootloader).


---

## 4. Стратегические решения (зафиксированы)

- **Converge ≠ merge.** Сведение к единой архитектуре (seL4 = единственное ядро,
  bare-metal-драйверы переезжают в Ring 3 домены) — **правильная цель**, но это
  фазированная **миграция с сохранённым fallback**, а не слияние.
- **Последовательность миграции:** сеть ✅ → IOMMU ⛔ → SMP ⛔ → хранилище.
  Bare-metal замораживается как «validation oracle» до полного parity; удаляется
  последним. IOMMU и SMP заблокированы upstream для MCS x86_64 (см. W6).
- **MLS 4/5:** оставить раздельно; при сведении — приоритет 5-уровневой MLS-схеме
  (зафиксировано `17ab786`, `b553dbf`).
- **IOMMU:** мониторить upstream; не блокировать W2. До работающего VT-d сведённую
  систему честно подписывать «process isolation; DMA isolation pending VT-d».
- **SMAP:** ✅ включён (`seL4-smap.patch`).
- **Fastpath:** включить и закрыть баг extra-caps **до** переноса сети (иначе
  IPC-латенция укусит на железе).

---

## 5. Вне текущего спринта (мониторинг)

- IOMMU/VT-d — до фикса upstream (sporadic SC race).
- SchildFS write-path — ✅ валидирован (QEMU + NVMe: Create→Write→Read-verify).
- x86_64 MCS формально верифицирован слабее ARM MCS — отразить в assurance-кейсе.
- **ARM64 (AArch64):** сетевой полигон под `qemu-arm-virt` валидирован (см. §6); цель — Pi 4B (BCM2711) + полное доказательство + SMP; SMMU отсутствует (DMA-изоляция вне скоупа).

---

## 6. ARM64 (AArch64) — сетевое направление (2026-10-24)

Ветка `arm64` (HEAD `6c61f04`) — virtio-net в QEMU `qemu-arm-virt` как
валидационный полигон перед целевой платформой **Raspberry Pi 4B** (BCM2711,
верифицированная AArch64). Сеть здесь — средство валидации seL4+AArch64, а не
продакшн-стек; на Pi 4 сетевая карта — **GENET**, а не virtio-net.

### 6.1 Валидировано (QEMU `-M virt`, SLIRP + hostfwd)

| Компонент | Статус | Проверка |
|---|---|---|
| seL4 AArch64: elfloader → ядро → root task | ✅ | `build_root.sh` + QEMU, `Hello ... (AArch64 root task)` |
| virtio-net: MMIO map + MAC под seL4 | ✅ | `virtio-net MAC = 52:54:00:12:34:56` |
| Протокол: ARP→ICMP→DHCP→TCP/HTTP→TCP-сервер→DNS | ✅ | `virtio-net DNS: OK (child)` |
| Кольцо дескрипторов (split-ring RX-пул + ротация TX) | ✅ | полный прогон, `[irq] N` |
| IRQ через seL4 Notifications + waiter-тред (`seL4_Wait`) | ✅ | `[irq] 31–49` |
| Разделение драйвер (`virtio_net.h`) / тест (`net_test.c`) | ✅ | `build_root.sh` |
| Изоляция: драйвер IRQ-пути + протокол в child-домене (свой CSpace, общий VSpace) | ✅ | `virtio-net DNS: OK (child)` |
| Полная process-изоляция: net-драйвер + протокол в ELF-child с отдельным VSpace | ✅ | `virtio-net: OK (own VSpace + ELF child)` |

### 6.2 Осталось (по приоритету)

1. **Процесс:** решить судьбу `master`, зафиксировать `libarchive-c` в
   окружении сборки. CI-автоматизация ✅ (`.github/workflows/arm64-net.yml`).
2. **Целевое железо:** драйвер **GENET** (Pi 4) — **блокирован железом**: QEMU
   `raspi4b` не эмулирует GENET (проверено по исходникам QEMU); seL4 `bcm2711`
   собирается, но валидировать драйвер без «Малинки» негде.

Детали и gotchas — `docs/technical/SESSION_ARM64_NET.md`.

---

## 7. Векторы развития (стратегия, рационально)

Дополняет §4 «Стратегические решения». Подробности и разметка
«[сейчас] / [позже] / [не делаем]» — в `docs/technical/DEVELOPMENT_VECTORS.md`.

Коротко:

- **Референтные кодовые базы (Kernkonzept / L4Re / Fiasco.OC)** — GPL-2.0,
  совместимо. Берём **принципы** (IO-сервер, DDE-порт Linux-драйверов, референс
  `bcmgenet.c` для GENET), но **не переносим код напрямую** (другой ABI) и **не
  переезжаем с seL4**.
- **High-assurance (подготовка к DO-178C / DO-333)** — технологически сильны
  (seL4 + SPARK), процессно слабы. Делаем по ценности: (1) требования + трассируемость,
  (2) покрытие кода (gcov/gnatcov) в CI, (3) план квалификации инструментов.
  Полную сертификацию не начинаем без реальной цели/органа.

Правило: **берём полезное, не упираемся в то, что не даёт практического результата.**
