# Schild TCB — Паспорт проекта

> Единый обзорный документ для инженеров, принимающих проект.
> Актуально на 25.09.2026. Каноничные детали — в `docs/technical/ASSURANCE.md`.

**Разработчик:** Ирганов А.Н.
**Статус:** научно-исследовательский прототип; ограниченное распространение.
**Платформа:** Intel x86_64 (Long Mode, SMP) · QEMU · ThinkPad T580.
**Языки:** Ada/SPARK 2022 + C + ASM. **Микроядро:** seL4 (прекомпилированное).

---

## 1. Назначение

Schild TCB — исследовательский прототип доверенной вычислительной базы (TCB)
и среды изолированной периферии. Цели:

- формальная верификация ядра (SPARK, уровень 4);
- мандатное управление доступом (MLS Bell-LaPadula);
- изоляция некритичной периферии (сеть, NVMe) в домены микроядра seL4.

**Достижения текущей версии:**

- 183 модуля ядра в proof-наборе, SPARK Level 4, `not-proved: 0`.
- 4 демона root-задачи доказаны в `verify.gpr` (Level 4).
- Сборка: 179 объектов (базовая) / 184 (полная), 0 ошибок.
- Загрузка с USB-флеш на ThinkPad T580; сетевой стек ARP/IPv4/ICMP/TCP/HTTP работает.
- Crash-containment NetServer продемонстрирован (QEMU).

## 2. Два образа (важно не путать)

| Образ | Сборка | Назначение | Где работает |
|---|---|---|---|
| `schild_os.iso` | `./build.sh` (default) | **bare-metal**: boot.S + GOP-фреймбуфер, ECAM→NVMe→сеть, SMP | T580 ✅ · QEMU ✅ |
| `sel4_primary.iso` | `SEL4_PRIMARY=1 ENABLE_DISTRIBUTED_LEDGER=0 ./build.sh` | **verification**: seL4 + Ada root-задача, crash-containment | только QEMU ⚠️ |

⚠️ `sel4_primary.iso` **не для T580**: у seL4-ядра Multiboot2-заголовок без тега
фреймбуфера, вывод root-задачи идёт в serial, а на T580 нет COM-порта.

## 3. Структура репозитория

```
SchildTCB/
├── src/schild_core/                  Ядро + сборка
│   ├── boot.S                        Вход: Multiboot2 → Long Mode → Ada-ядро
│   ├── src/01_hardware/              HAL: MMU, APIC/IOAPIC, NVMe, e1000e, SMP, PIT
│   ├── src/02_security/              MLS, cap-space, IPC-шлюз, файрвол
│   ├── src/03_crypto/                AES-NI, SHA-256, HMAC, ГПСЧ
│   ├── src/04_userland/              VFS/SchildFS, сокеты, сетевой стек
│   ├── src/*.adb / *.c / *.h         Ядро: schild_core, kernel_entry, boot_runtime
│   ├── bare_runtime/                 GNAT-рантайм (сторонний, GMGPL)
│   ├── tools/sel4/                   Интеграция seL4
│   │   ├── kernel.elf                Прекомпилированное ядро seL4 (GPL-2.0, ~186 КБ)
│   │   ├── src/                      Ada root-задача + C-шимсы (netserver, config_daemon, …)
│   │   └── tests/                    KAT-тесты (acpi/aes/hmac)
│   ├── build.sh                      Точка входа сборки (двухконтурная)
│   ├── Makefile / *.gpr              Альтернативная сборка / проекты
│   └── scripts/                      prove_kernel.sh, verify.sh, run_tests.sh, sanitize_paths.sh
├── private/                          Проприетарные модули (оверлей SCHILD_PROFILE=private)
│   ├── userland/                     Ledger (TON/Web3), Wasm-песочница
│   └── root_task/                    Audit Logger, Config Daemon, Boot Manager, net_runtime
├── docs/                             Документация (technical + academic)
├── patches/                          Патч к seL4 (обнуление объектов)
├── tools/                            Вспомогательные утилиты
├── README.md                         Описание программы (ГОСТ)
├── PROJECT_PASSPORT.md               Этот файл
├── NOTICE.md                         Правовой статус + третьесторонние лицензии
└── LICENSE                           Проприетарная лицензия
```

## 4. Архитектура

### 4.1. Двухконтурная сборка

`SCHILD_PROFILE=public` (по умолчанию) — базовая версия, коммерческие модули
заменены заглушками (stub). `SCHILD_PROFILE=private` — полная версия: `build.sh`
и `tools/sel4/build_rt.sh` копируют реальные `.adb`-тела из `private/` поверх
заглушек и включают реестр (`ENABLE_DISTRIBUTED_LEDGER=1`).

### 4.2. Слои ядра (автономная конфигурация)

| Слой | Назначение |
|---|---|
| `01_hardware` | Управление оборудованием: MMU, APIC/IOAPIC, NVMe, e1000e, SMP, PIT |
| `02_security` | MLS Bell-LaPadula, cap-space, шлюз IPC, файрвол |
| `03_crypto` | AES-NI, SHA-256, HMAC-SHA256 (FIPS 198-1), ГПСЧ |
| `04_userland` | SchildFS/VFS, сокеты, сетевой стек (ARP/IPv4/TCP/UDP/HTTP) |

### 4.3. Конфигурация seL4

Root Task (Ada/SPARK) порождает изолированные процессы: MLS-сервер
(Bell-LaPadula), Config Daemon (транзакционный конфиг), NetServer (e1000e + TCP/IP
в Ring 3). Взаимодействие — только через syscall ABI seL4.

### 4.4. MLS (мандатный доступ)

- Интеграционный слой seL4 — **5 уровней**: Public, Internal, Confidential,
  Secret, Top_Secret (`Schild_Config_Daemon.Security_Level`).
- Автономное bare-metal ядро — **4 уровня** (`Clear_Level_Type 1..4`).

Расхождение числа уровней (4/5) на стыке интеграционных интерфейсов является известной особенностью текущего прототипа и изолировано на уровне C-шимсов пространства пользователя seL4 (NetServer), не нарушая 4-уровневую математическую строгость доказанного SPARK-движка автономного ядра.

### 4.5. Планировщик

Честное прерывание PIT (канал 0, ~100 Гц, IRQ0 → вектор 0x20); idle через
`sti`/`hlt`. Busy-wait отсутствует (`schild_kernel_logic.adb`).

## 5. Модель доверия

Три тира кода:

- **A — доказанное ядро** (SPARK, 0 unproved): MLS-политика, cap-space, таблица
  процессов, вердикты файрвола.
- **B — изолированная периферия** (containment): e1000e, NVMe, сетевой стек.
- **C — скаффолд** (не реализован в базовой сборке): полный файрвол, крипто.

TCB: верифицированные модули (`SPARK_Mode => On`) + неверифицированный ring-0
(`boot.S`, `runtime_stubs.c`, `interrupt_handlers.c`, `hw_io.c`).

## 6. Сборка и запуск

Требования: GNAT/gprbuild (Alire `gnat_native` 14.2.1), grub-mkrescue, QEMU.

```bash
cd src/schild_core

# Автономное ядро (bare-metal)
./build.sh

# Полная версия (оверлей проприетарных модулей из private/)
SCHILD_PROFILE=private ./build.sh

# Интеграция seL4 (root-задача), для QEMU
SEL4_PRIMARY=1 ENABLE_DISTRIBUTED_LEDGER=0 ./build.sh

# Формальная верификация
bash scripts/verify.sh          # 4 демона root-задачи, Level 4
bash scripts/prove_kernel.sh    # полный прогон ядра (183 модуля)

# Прогон в QEMU
SKIP_BUILD=1 SEL4_PRIMARY=0 bash scripts/run_tests.sh

# Образ файловой системы
python3 mkschildfs.py test_disk.img
```

Запись на флешку (T580):
```bash
sudo dd if=schild_os.iso of=/dev/sdX bs=4M status=progress oflag=sync && sync
```

## 7. Верификация

| Проверка | Команда | Результат |
|---|---|---|
| Сборка (базовая) | `./build.sh` | 179 объектов, 0 ошибок |
| Сборка (полная) | `SCHILD_PROFILE=private ./build.sh` | 184 объекта, 0 ошибок |
| Доказательство ядра | `scripts/prove_kernel.sh` | 183 модуля, `not-proved: 0` |
| Демоны root-задачи | `scripts/verify.sh` | все VC доказаны |
| Boot smoke (standalone) | `run_tests.sh` | Long Mode → e1000e → SMP → MLS → :80 |
| Crash-containment | `SEL4_PRIMARY=1 run_tests.sh` | `[FAULT] Caught fault` + `[CONTAINMENT] core alive` |

## 8. Ключевые подсистемы и статус

| Подсистема | Статус | Детали |
|---|---|---|
| NVMe | ✅ runtime-tested | Identify + Read + Write + Verify (QEMU + T580) |
| e1000e | ✅ runtime-tested | TX/RX/ARP/ICMP/TCP/HTTP; IRQ-driven RX **не валидирован** |
| SMP | ✅ runtime-tested | BSP + AP (7 ядер на T580) |
| SchildFS | 🟡 | read-only в boot-path; write-path (A/B суперблок) не проверен |
| MLS Bell-LaPadula | ✅ verified + tested | доказано + 8/8 runtime-тестов |
| HMAC-SHA256 | ✅ tested | FIPS 198-1 |
| seL4 Root Task / NetServer | ✅ (SEL4_PRIMARY) | изоляция + crash-containment |
| Firewall / крипто / реестр | 🔒 private | заглушки в базовой сборке |

## 9. Известные ограничения и латентные дефекты

1. **Fault-обработчики MLS (слот 199) и Config Daemon (слот 526)** — объекты типа
   Notification; non-MCS seL4 требует endpoint. Латентный дефект (эти потоки
   сейчас не фолтят в тестах). Root-задача: endpoint на слоте 500 — корректно.
2. **e1000e IRQ-driven RX** — прерывания (GSI/IRQ через Notifications seL4)
   разведены, но на железе не валидированы.
3. **SchildFS write-path** — не проверен (только read-only в boot-path).
4. **IOMMU (P0-3)** — изоляция устройств после снятия device-bypass — TODO.
5. **seL4 MCS** — нет проверенной конфигурации X64_MCS (временная изоляция).
6. **`sel4_primary.iso`** — артефакт для QEMU, не для T580 (см. §2).

## 10. Правовой статус

Собственный код — объект интеллектуальной собственности, статус «ограниченного
распространения» (см. `LICENSE`). Третьесторонние компоненты — под своими
лицензиями (seL4 — GPL-2.0-only; GNAT runtime — GMGPL; патч — GPL-2.0-only);
полный перечень — в `NOTICE.md`.

## 11. Карта ключевых файлов

| Файл | Что делает |
|---|---|
| `src/schild_core/boot.S` | Вход ядра: Multiboot2 → Long Mode → Ada |
| `src/schild_core/src/schild_core.adb` / `schild_kernel_entry.adb` | Инициализация ядра |
| `src/schild_core/src/01_hardware/schild_kernel_logic.adb` | Планировщик (PIT) |
| `src/schild_core/src/02_security/schild_mls_core_engine.ads` | MLS (bare-metal, 4 уровня) |
| `src/schild_core/tools/sel4/src/schild_mls_policy.ads` | MLS-политика (seL4, 5 уровней) |
| `src/schild_core/tools/sel4/src/schild_root_task.adb` | Root-задача seL4 |
| `src/schild_core/tools/sel4/src/schild_sel4_syscall.adb` | Связка syscall seL4 (fault-обработчики) |
| `src/schild_core/build.sh` | Двухконтурная сборка |

## 12. Дальнейшее чтение

- `docs/technical/ASSURANCE.md` — каноничный assurance case (цели, TCB, фазы).
- `docs/technical/ARCHITECTURE.md` — технический data-sheet.
- `docs/technical/SECURITY.md` — модель безопасности (CVE, MLS).
- `docs/technical/SEL4_INTEGRATION.md` — история интеграции seL4.
- `docs/technical/CHANGELOG.md` — журнал изменений (только проверенные результаты).
- `NOTICE.md` — правовой статус и третьесторонние лицензии.
