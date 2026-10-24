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

- 185 модулей ядра в proof-наборе, SPARK Level 4, `not-proved: 0`.
- 7 демонов root-задачи доказаны в `verify.gpr` (Level 4): MLS, Config, Audit,
  Boot, HM Model, Launch Model, Root Task.
- Сборка: 179 объектов (базовая) / 184 (полная), 0 ошибок.
- Загрузка с USB-флеш на ThinkPad T580; сетевой стек ARP/IPv4/ICMP/TCP/HTTP работает.
- Crash-containment NetServer продемонстрирован (QEMU).

## 2. Два образа (важно не путать)

| Образ | Сборка | Назначение | Где работает |
|---|---|---|---|
| `schild_os.iso` | `./build.sh` (default) | **bare-metal**: boot.S + GOP-фреймбуфер, ECAM→NVMe→сеть, SMP | T580 ✅ · QEMU ✅ |
| `sel4_primary.iso` | `SEL4_PRIMARY=1 ./build.sh` | **verification**: seL4 + Ada root-задача, crash-containment | QEMU ✅ · T580 ✅ (boot) |

ℹ️ `sel4_primary.iso` загружается на T580 (32 ГБ) с 2026-10-04: фреймбуферная
консоль (`seL4-framebuffer-*.patch`) + 8 КБ BootInfo + 500 untyped-капсул →
`==== Root Task ready ====`. Сетевой путь seL4-NetServer валидирован на T580
(W2): реальная I219-V (`0xE8200000`) через ECAM+MSI, IRQ-driven RX, end-to-end
TCP/HTTP; QEMU-фолбэк (82540EM) сохранён.

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
├── private/                          Полные реализации демонов (оверлей SCHILD_PROFILE=private)
│   └── root_task/                    Audit Logger, Config Daemon, Boot Manager, net_runtime
├── docs/                             Документация (technical + academic)
├── patches/                          Патч к seL4 (обнуление объектов)
├── tools/                            Вспомогательные утилиты
├── README.md                         Описание программы
├── PROJECT_PASSPORT.md               Этот файл
├── NOTICE.md                         Правовой статус + третьесторонние лицензии
└── LICENSE                           GPL-2.0-only
```

## 4. Архитектура

### 4.1. Двухконтурная сборка

`SCHILD_PROFILE=public` (по умолчанию) — базовая версия, коммерческие модули
заменены заглушками (stub). `SCHILD_PROFILE=private` — полная версия:
`tools/sel4/build_rt.sh` копирует реальные `.adb`-тела из `private/root_task/`
поверх заглушек.

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

- Интеграционный слой seL4 — **5 уровней** (MLS-схема): Public, Internal,
  Confidential, Secret, Top_Secret (`Schild_Config_Daemon.Security_Level`).
- Автономное bare-metal ядро — **4 уровня**:
  Public, Restricted, Confidential, Secret (`Clear_Level_Type 1..4`).

Расхождение — не просто «4 против 5», а **две разные схемы классификации**:
в bare-metal 2-й уровень называется *Restricted* и нет *Top_Secret*; в seL4
2-й уровень — *Internal* и добавлен *Top_Secret*. Эти модели живут в **разных
образах** (standalone vs seL4) и не имеют общего рантайм-стыка, поэтому расхождение
не нарушает математическую строгость доказанного SPARK-движка автономного ядра.
Соответствие задокументировано перекрёстными ссылками в обоих местах определения
(`schild_mls_core_engine.ads`, `schild_config_daemon.ads`).

**Решение (2026-10-03):** оставить раздельно. Если в будущем потребуется свести
модели, приоритет — в сторону **5-уровневой MLS-схемы** (Public..Top_Secret).

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
SEL4_PRIMARY=1 ./build.sh

# Формальная верификация
bash scripts/verify.sh          # 7 демонов root-задачи, Level 4
bash scripts/prove_kernel.sh    # полный прогон ядра (185 модулей)

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
| Доказательство ядра | `scripts/prove_kernel.sh` | 185 модулей, `not-proved: 0` |
| Демоны root-задачи | `scripts/verify.sh` | все VC доказаны |
| Boot smoke (standalone) | `run_tests.sh` | Long Mode → e1000e → SMP → MLS → :80 |
| Crash-containment | `SEL4_PRIMARY=1 run_tests.sh` | `[FAULT] Caught fault` + `[CONTAINMENT] core alive` |

## 8. Ключевые подсистемы и статус

| Подсистема | Статус | Детали |
|---|---|---|
| NVMe | ✅ runtime-tested | Identify + Read + Write + Verify (QEMU + T580); **изолирован в seL4 NetServer (W7)** |
| e1000e | ✅ runtime-tested | TX/RX/ARP/ICMP/TCP/HTTP; IRQ-driven RX **валидирован** (MSI+hlt, T580) |
| SMP | ✅ runtime-tested | BSP + AP (7 ядер на T580) |
| SchildFS | ✅ | read + write validated (QEMU + NVMe: Create→Write→Read-verify) |
| MLS Bell-LaPadula | ✅ verified + tested | доказано + 8/8 runtime-тестов |
| HMAC-SHA256 | ✅ tested | FIPS 198-1 |
| seL4 Root Task / NetServer | ✅ (SEL4_PRIMARY) | изоляция сети (W2) + хранилища (W7) + crash-containment |
| Firewall / крипто | 🔒 private | заглушки в базовой сборке |

## 9. Известные ограничения и латентные дефекты

1. **Fault-обработчики MLS (слот 199) и Config Daemon (слот 526)** — ✅ исправлено
   (`4f87475`): были Notification, переведены на endpoint (non-MCS seL4 требует
   endpoint для корректной доставки fault-сообщения). Root-задача: endpoint 500.
2. **e1000e IRQ-driven RX (seL4 NetServer)** — ✅ валидирован на T580 (W2):
   реальная I219-V (`0xE8200000`) через ECAM+MSI, IRQ-driven RX (Notification,
   badge `0xE1`), end-to-end TCP/HTTP. Автономное ядро: IRQ-driven RX (MSI+hlt)
   валидирован на T580.
3. **SchildFS write-path** — ✅ валидирован (QEMU + NVMe: Create→Write→Read-verify).
4. **IOMMU (P0-3)** — изоляция устройств после снятия device-bypass — TODO.
5. **seL4 MCS** — ✅ QEMU-валидирован (temporal isolation: CPU-бюджеты,
   sporadic Config Daemon → `seL4_Fault_Timeout`). Формально верифицирован слабее
   ARM MCS (upstream).
6. **Fastpath** — опция `KERNEL_FASTPATH=ON` (default OFF, parity с
   `X64_verified`). На MCS баг extra-caps не воспроизводится (W5).

## 10. Правовой статус

Собственный код распространяется под лицензией **GPL-2.0-only** (см. `LICENSE`).
Третьесторонние компоненты — под своими лицензиями (seL4 — GPL-2.0-only;
GNAT runtime — GMGPL; патч — GPL-2.0-only); полный перечень — в `NOTICE.md`.

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
