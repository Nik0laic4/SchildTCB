# Schild TCB

Формально верифицированная **доверенная вычислительная база (TCB)** и среда изолированной периферии на **Ada/SPARK 2022** поверх микроядра **seL4**.

[![License: GPL-2.0-only](https://img.shields.io/badge/License-GPL--2.0--only-blue.svg)](LICENSE)
[![SPARK Level 4](https://img.shields.io/badge/SPARK-Level_4-not--proved:0-green)](docs/technical/ASSURANCE.md)

---

## Что это

Schild TCB — исследовательский прототип доверенной вычислительной базы на микроядерной архитектуре. Это **два артефакта, а не один**:

1. **Автономная ОС (bare-metal)**, написанная с нуля на Ada — загрузчик, драйвер NVMe, драйвер e1000e, стек TCP/IP, HTTP-сервер. Работает на ThinkPad T580 и в QEMU. Отвечает на вопрос *«работает ли?»*.
2. **Слой seL4** — микроядро оригинальное (upstream, формально верифицированное), вклад проекта — **root-задача** на Ada/SPARK и несколько демонов. Сеть и хранилище работают **изолированно в Ring 3**, общаясь через IPC. Отвечает на вопрос *«доказано ли?»*.

## Ключевые характеристики

- **Формальная верификация** — 185 модулей ядра верифицированы на **4-м уровне строгости SPARK** (`gnatprove --level=4 --mode=all`), результат **`not-proved: 0`**. Ещё 7 демонов root-задачи (политика MLS, конфигурационный демон, журнал аудита, A/B-загрузчик, HM-модель, launch-модель, root-задача) доказаны.
- **Изолированная периферия** — сеть (e1000e → I219-V) и хранилище (NVMe + SchildFS) работают в изолированном Ring-3 **NetServer**; сбой там не достигает доказанного ядра.
- **MLS Bell-LaPadula** — 5 уровней в слое seL4 (Public..Top_Secret), 4 в bare-metal ядре.
- **Сдерживание сбоев** — сбой драйвера перехватывается и изолируется без перезагрузки платформы.
- **Загрузка на реальном железе** — ThinkPad T580 (32 ГБ) и QEMU.

## Архитектура

| Слой | Назначение |
|------|-----------|
| `01_hardware` | MMU, APIC/IOAPIC, NVMe, e1000e, SMP, таймер PIT |
| `02_security` | MLS Bell-LaPadula, модель возможностей, шлюз IPC, файрвол |
| `03_crypto` | AES-NI, SHA-256, HMAC-SHA256 (FIPS 198-1), ГПСЧ |
| `04_userland` | SchildFS/VFS, сокеты, сетевой стек (ARP/IPv4/TCP/UDP/HTTP) |

## Статус верификации (честные границы)

| Уровень | Код | Утверждение |
|---------|-----|-------------|
| **A — Доказанное ядро** | политика MLS, модель возможностей, таблица процессов, вердикты файрвола | *Формально верифицировано* (SPARK, 0 непроверенных VC) |
| **B — Изолированная периферия** | e1000e, NVMe, сетевой стек | *Сдержано* — компрометация не достигает уровня A |
| **C — Каркас** | крипто фильтра пакетов, полные правила файрвола | *Не реализовано в этой сборке*, явно помечено |

Драйверы (NVMe, e1000e, сетевой стек) **не доказаны** и не заявляются таковыми — у аппаратуры нет формальной спецификации. Вместо этого они изолированы в отдельные домены.

Известные ограничения upstream (не в этом коде):

- **IOMMU (VT-d)** — experimental/flaky upstream (спорадическая гонка scheduling-context на x86_64 MCS). DMA-изоляция отложена.
- **SMP** — `KernelMaxNumNodes` форсируется в 1 на x86_64 **MCS** (ограничение upstream).
- **x86_64 MCS** формально верифицирован **слабее, чем ARM MCS** (официальный статус upstream).

## Порт ARM64 (ветка `arm64`)

Ветка **`arm64`** нацелена на **Raspberry Pi 4B** (BCM2711) — **формально верифицированную AArch64**-платформу seL4 (4× Cortex-A72, SMP, отладка по UART):

- Полный цикл в QEMU работает: ELF loader → ядро seL4 → root task → вывод по UART.
- **virtio-net в QEMU** — валидирован end-to-end: ARP → ICMP → DHCP → TCP/HTTP → TCP-сервер → DNS, с split-ring кольцом дескрипторов, IRQ через seL4 Notifications (блокирующий `seL4_Wait` в waiter-треде) и драйвером + протоколом в **изолированном child-домене** со своим CSpace.
- Инструментарий: QEMU aarch64, `gcc/g++-aarch64-linux-gnu`, `gnat-aarch64`, `repo`, `protoc`, `dtc`.
- У Raspberry Pi **нет SMMU**, поэтому DMA-изоляция на этой платформе вне скоупа.

См. [`src/schild_core/arm64/README.md`](src/schild_core/arm64/README.md).

## Сборка (x86_64)

Требования: GNAT (Ada/SPARK 2022) + gprbuild (рекомендуется Alire `gnat_native` 14.2.1), grub-mkrescue, QEMU.

```bash
cd src/schild_core

# Автономное ядро (bare-metal)
./build.sh

# Интеграционный слой seL4 (root-задача Ada/SPARK), QEMU
SEL4_PRIMARY=1 ./build.sh

# Формальная верификация
bash scripts/verify.sh          # демоны root-задачи, SPARK Level 4
bash scripts/prove_kernel.sh    # полный прогон ядра (185 модулей)

# Прогон в QEMU
SKIP_BUILD=1 SEL4_PRIMARY=0 bash scripts/run_tests.sh
```

## CI (GitHub Actions)

- **Push / PR в `master`** → автоматически выполняются `build` (bare-metal ядро + ISO) и `verify` (7 демонов root-задачи, SPARK Level 4).
- **Вручную** (`Actions` → `CI` → *Run workflow*) → задача `prove-full` выполняет полное доказательство 185 модулей на SPARK Level 4 (`scripts/prove_kernel.sh`) и загружает `obj/proof/report.txt` как артефакт.

## Документация

- [`PROJECT_PASSPORT.md`](PROJECT_PASSPORT.md) — обзор проекта.
- [`docs/technical/ASSURANCE.md`](docs/technical/ASSURANCE.md) — assurance-кейс и план укрепления.
- [`docs/technical/ARCHITECTURE.md`](docs/technical/ARCHITECTURE.md) — технический data-sheet.
- [`docs/technical/ROADMAP.md`](docs/technical/ROADMAP.md) — каноничное «что дальше».
- [`docs/technical/CHANGELOG.md`](docs/technical/CHANGELOG.md) — только проверенные результаты.
- [`docs/SCHILD_TCB_AUDIT_REPORT.md`](docs/SCHILD_TCB_AUDIT_REPORT.md) — независимый технический обзор.

## Лицензия

Собственный код проекта распространяется под **GPL-2.0-only** (см. [`LICENSE`](LICENSE)). Сторонние компоненты — под своими лицензиями, см. [`NOTICE.md`](NOTICE.md):

- Микроядро seL4 — GPL-2.0-only (Data61/CSIRO)
- GNAT Runtime Library — GMGPL (GPL + runtime exception)

## Автор

Александр Ирганов (Alexander Irganov).

- Хабр: [«Микроядро seL4, Ada/SPARK и 185 модулей: разбор проекта»](https://habr.com/ru/articles/1095314/)
- vc.ru: [«Зачем сварщику микроядро?»](https://vc.ru/id79615/3203908-zachem-svarshchiku-mikroyadro-sel4-i-proyekt-schild-tcb-na-ada-spark)
- Reddit (r/ada): [«I'm a 38-year-old welder…»](https://www.reddit.com/r/ada/s/XSFhtr1EzA)

© 2026 Александр Ирганов.
