# Schild TCB — Векторы развития (стратегия)

**Version:** v1.2 | **Date:** 2026-10-31
**Status:** рабочий план «что даёт практический результат».

> **Принцип:** берём всё, что реально полезно, но не упираемся там, где практический
> результат почти нулевой. Каждый пункт помечен `[сейчас]` / `[позже]` / `[не делаем]`
> с обоснованием. Это дополняет `ROADMAP.md` (§4 «Стратегические решения»).

---

## 1. Референтные кодовые базы — Kernkonzept / L4Re / Fiasco.OC

### Что это

- **Fiasco.OC** — микроядро L4-семейства (капабилити-based); **L4Re** — юзерленд-рантайм
  поверх него (драйверы, `uvmm`, `Ned`/`Moe`/`Sigma0`). Коммерциализирует **Kernkonzept**.
- Лицензии: Fiasco.OC и L4Re — **GPL-2.0** (часть — BSD). Ядро seL4 — GPL-2.0, libsel4 — BSD-2.
  Наш код — GPL-2.0. **Смотреть и заимствовать можно легально**, с атрибуцией.
- Открытый снимок: `github.com/kernkonzept/l4re-snapshot`, `fiasco`.

### Что берём (принципы, не код)

| Что | Зачем | Метка |
|---|---|---|
| Модель **IO-сервера** (домен владеет MMIO+IRQ+DMA) | свериться с нашей декомпозицией (у нас уже есть) | `[сейчас]` — анализ |
| **DDE** — порт Linux-драйверов в микроядро | ключ к будущему GENET | `[сейчас]` — изучить паттерн |
| `bcmgenet.c` (Broadcom GENET, Linux/L4Re) | референс регистров/колец/IRQ для драйвера Pi 4 | ✅ конспект `GENET_DRIVER_DESIGN.md`; `[позже]` — порт под seL4 |
| virtio/e1000e драйверы L4Re | сверка с нашим virtio-net | ✅ `VIRTIO_NET_L4RE_COMPARISON.md` |
| `uvmm` (VMM) | виртуализация — референс гипервизорного вектора (§4) | `[позже]` — см. §4 |

### Что НЕ делаем

- **Прямой перенос кода L4Re** — другой syscall ABI / IPC / объекты ядра. `[не делаем]`
- **Переезд на Fiasco.OC / L4Re** — мы на seL4 (формально верифицирован). `[не делаем]`

---

## 2. High-assurance — подготовка к DO-178C / DO-333

### Контекст и ограничения

- **DO-178C** — стандарт **процесса** разработки авиационного ПО (DAL A–E; A = катастрофический).
  Это про **требования, трассируемость, покрытие, верификацию**, а не про сам код.
- **DO-333** — дополнение про **формальные методы** (разрешает заменять часть тестов
  формальным доказательством).
- **Важно:** DO-178C — про **авиацию**. Для security-TCB (наш «КИБЕРЩИТ»-контекст)
  релевантнее **Common Criteria (ISO/IEC 15408)**, но **инженерное ядро
  (формальная верификация + трассируемость + покрытие + квалификация инструментов)
  общее для всех high-assurance стандартов**.

### Текущая позиция

| Аспект | Статус |
|---|---|
| Формально верифицированное ядро (seL4) | ✅ (с оговорками: доказательство для конкретной конфигурации) |
| SPARK/Ada + формальное доказательство (Level 4) | ✅ |
| Модульная архитектура (root task + daemons + child-домены) | ✅ |
| Требования с ID + трассируемость | ⚠️ есть ROADMAP/ARCHITECTURE, но не формальные spec |
| Покрытие кода (statement/branch/MC-DC) | ❌ нет систематического измерения |
| Квалификация инструментов | ❌ нет плана |
| Процесс / PSAC / независимость верификации | ❌ нет |

### Что делаем (по убыванию «ценность/усилия»)

1. **Требования с ID + матрица трассировки** (требование → дизайн → код → тест). ✅
   Пилоты: `REQUIREMENTS_ARM64_NET.md` (ARM64 net) + `REQUIREMENTS_BOOT_RELIABILITY.md`
   (фаза надёжности: boot counter / health check / watchdog). Дальше — ID-комментарии
   в коде + покрытие в CI.
2. **Покрытие кода в CI**: `gcov` (C) ✅ пилот `build_proto_test.sh` (`net_test.c`);
   `gnatcov` (Ada, MC/DC) — дальше. `[сейчас]` — измеримо, ловит «мёртвый код».
3. **DO-333**: расширить SPARK-доказательства на большее число модулей
   (замена части тестирования формальным доказательством). `[позже]` — по мере роста кода.
4. **План квалификации инструментов**: ✅ `TOOL_QUALIFICATION.md` — зафиксированы версии
   GNAT/gnatprove/gprbuild/seL4, детерминизм (`SOURCE_DATE_EPOCH`, prefix-map, backend `-14`),
   известный недетерминизм (`gnatprove -j8`) и шаги к DO-330/DO-333.
5. **PSAC / полный процесс сертификации**: `[не делаем]` — годы работы + сертифицирующий
   орган + DER; начинать только при реальной цели сертификации и заказчике.

---

## 3. Сводный приоритет (что прямо сейчас)

| # | Действие | Направление | Метка |
|---|---|---|---|
| 1 | Требования + трассируемость ✅ (ARM64 net + boot/reliability) | high-assurance | `[сделано]` — `REQUIREMENTS_ARM64_NET.md`, `REQUIREMENTS_BOOT_RELIABILITY.md` |
| 2 | Покрытие кода (gcov/gnatcov) в CI | high-assurance | `[сейчас]` |
| 3 | Конспект дизайна GENET ✅ `GENET_DRIVER_DESIGN.md` | референтные базы | `[сейчас]` |
| 4 | Сверка нашего virtio-net с L4Re ✅ `VIRTIO_NET_L4RE_COMPARISON.md` | референтные базы | `[сейчас]` |
| 5 | Драйвер GENET (порт под seL4) | референтные базы | `[позже]` — ждём Pi 4 |
| 6 | Контрактный аудит Tier-A ✅ + модель угроз ✅ | high-assurance | `[сделано]` (`THREAT_MODEL.md`, `CHANGELOG.md` W8); расширение на сеть ✅ (arp/icmp/ipv4/udp/tcp доказаны), осталось крипто/ядро — `[в работе]` |
| 7 | Фаза надёжности: boot counter ✅ (W9.1) + health check ✅ (W9.2) + watchdog логика ✅ (W9.3) → таймер/tryboot (железо) | boot/update/recovery | `[железо]` — next: хардварный таймер + bootloader |
| 8 | Гипервизор Type-1: VMM в Ring 3 + virtio-эмуляция + Linux guest (ИИ-агенты) | гипервизор | `[позже]` — после Точки С и H87, см. §4 |
| — | Прямой перенос кода L4Re / переезд на Fiasco.OC | референтные базы | `[не делаем]` |
| — | Полная сертификация DO-178C DAL A | high-assurance | `[не делаем]` без заказчика/органа |

---

## 4. Вектор гипервизора (Type-1) — после Точки С

**Статус:** запланировано, не начато. Предпосылки не выполнены.
**Точка входа:** после закрытия Блока 3 (H87 ELF loader, AS6, C1) и Точки С (Assurance Case).
**Не начинать раньше:** VMM в shared image RW = OOB из virtio повреждает `.bss` FS daemon. H87 — жёсткая предпосылка, не опциональная.

### Цель

Долгосрочно Schild TCB должен работать как **формально верифицированный гипервизор Type-1**:
запускать стандартный Linux-дистрибутив как гостевую VM рядом с проверенным ядром. Гарантии
изоляции seL4 не дают скомпрометированному гостю покинуть свою VM.

### Сценарий

Безопасное выполнение **автономных ИИ-агентов**: гостевой Linux получает инструменты и сеть,
а доказанная изоляция seL4 гарантирует, что скомпрометированный или галлюцинирующий агент не
выйдет за пределы VM и не повредит хост или другие домены. Это же фундамент для
Qubes-подобной изоляции рабочей среды.

### Технически

- **VMM** — изолированный домен в Ring 3 (по образцу наших daemons, но со сложной логикой:
  CPU-виртуализация через VMM-поддержку seL4).
- **virtio-устройства** — эмуляция сети/диска/видео; **без PCIe passthrough** (IOMMU заблокирован
  upstream) — вся периферия эмулируется.
- **IPC к хостовым драйверам**: NetServer (сеть), FS Daemon (хранение).
- **Предпосылки из Б→С**: H87 (ELF loader / code isolation) — обязателен для корректной изоляции
  VM-образов; daemon-архитектура уже даёт нужный IPC-каркас.

### 4.0 Предпосылки (проверить перед стартом)

| # | Предпосылка | Почему обязательна | Статус |
|---|---|---|---|
| P1 | **H87 частично** — ELF loader + FS daemon CLOSED; MLS/Config/NetServer → Load_Elf open | Без него VMM в shared image = OOB в общий `.bss` всех daemons | ⏳ FS ✅ / MLS·Config·Net open |
| P2 | **Блок 3 CLOSED** — AS6 (syscall seam), C1 (ring-0 C) | VMM — новый Tier B компонент, зависит от стабильного seam | open |
| P3 | **Точка С** — Assurance Case готов | VMM — новая поверхность, добавлять до фиксации baseline нельзя | open |
| P4 | **H61 решён или официально out of scope** | Merkle tree audit (§4.2.6) — продолжение H61; без решения H61 весь пункт 3 откладывается | ✅ решён (H61 HMAC-SHA256, ключ детерминированный; RNG → Блок 3) |
| P5 | **TPM/secure element проверить** (T580 fTPM, Pi 4 нет) | Remote attestation (§4.2.7) без HWRoT = measured boot, не attestation | не проверено |

Если хотя бы P1/P3 не закрыты — вектор не начинать. P4/P5 влияют на 2 из 7 пунктов (можно начать с остальных).

### 4.1 Компоненты (по приоритету)

**Порядок:** 7 → 5 → 1 → 4 → 2 → 3 → 6. Каждый пункт — отдельный Tier B домен или расширение существующего.

| # | Компонент | Tier | Приоритет | Оценка | Предпосылки |
|---|---|---|---|---|---|
| 7 | **Guest awareness (SMBIOS/DT)** | B | первый (S) | S | нет |
| 5 | **stdout via virtio-console → Console daemon** | B | второй (S-M) | S-M | нет |
| 1 | **VMM (Rust или Ada)** | B | третий (L) | L | P1, P2 |
| 4 | **MCS Dashboard** | B | четвёртый (M) | M | VMM работает, manual accounting |
| 2 | **YAML Capability Manager** | A + B | пятый (M-L) | M-L | валидатор — Tier A, SPARK On |
| 3 | **Merkle tree / HMAC audit log** | B | шестой (M) | M | H61 решён |
| 6 | **Measured boot (опц. TPM quote)** | — | седьмой (M/L) | M/L | TPM есть |

### 4.2 Детали по компонентам

#### 4.2.1. Guest awareness (SMBIOS/DMI на x86, DT на ARM)
Гость получает имя «Schild TCB», версию, capabilities. Не security feature — UX и интеграция. Гость может адаптировать поведение.
- **Риск:** нет (информация публичная).
- **Реализация:** QEMU virtio-mmio dtb или SMBIOS-таблица в VMM.

#### 4.2.2. stdout через virtio-console в Console daemon
Гость пишет в virtio-console → VMM → Console daemon (Ring 3, свой audit.log).
- **Риск (T18):** гость подделывает формат audit event → подделка лога. Fix: префикс `GUEST:<vmid>:` + валидация (длина, UTF-8, no control chars) в Console daemon.
- **Риск:** три hop (guest → VMM → Console → FS) — latency. Для отладки приемлемо.
- **Альтернатива:** прямо в serial (UART) — проще, но не переживает reboot.

#### 4.2.3. VMM (Type-1, Rust или Ada)
**Rust:**
- Плюс: borrow checker для virtio (UAF/double-free — классика C-драйверов).
- Минус: поддержка seL4 x86_64 **MCS** (sched context, reply object, timeout endpoint) — проверить до выбора. Официальные биндинги (`sel4-rust`, `ferros`) сильнее на aarch64.
- Реализация: `no_std` + `unsafe` только в FFI-слое (sel4 syscalls).

**Ada/SPARK (альтернатива):**
- Плюс: единый язык с TCB, SPARK On для критичных частей (capability dispatch).
- Минус: virtio на SPARK — constrained buffers, без указательной арифметики, сложно.

**C (fallback):**
- Плюс: как NetServer, паттерн проверен.
- Минус: memory safety нет, containment единственный backstop.

**Решение:** проверить seL4 Rust на x86_64 MCS **до** начала. Если нет — Ada/SPARK (subset) или C+фаззинг. Периферия — только эмуляция virtio (NIC/blk/console); **без PCIe passthrough** (IOMMU заблокирован upstream).

#### 4.2.4. MCS Dashboard
Показывает CPU usage каждого sched context в реальном времени.
- **Проблема:** seL4 не даёт «сколько CPU потребил sched context» через API.
- **Вариант A (manual):** каждый daemon зовёт `Call(root, op=report_budget, used_cycles)` в конце работы. RDTSC. Приблизительно, без изменения kernel.
- **Вариант B (tracing kernel):** seL4 tracepoints, root task читает trace buffer. **Не verified config** — claim ломается.
- **Решение:** вариант A. Demo, не security.

#### 4.2.5. YAML Capability Manager
Декларативная конфигурация доменов вместо Ada-кода.
- **Валидация — часть TCB (T19):** capability schema: кто может дать что. «FS daemon — единственный, кому можно NVMe», «VMM может получить только virtio-NIC и virtio-blk». Слабая валидация = privilege escalation через YAML.
- **Парсер:** YAML на Rust (memory-safe) или свой constrained формат (TOML без вложенности). SPARK YAML-парсер — долго, не оправдан.
- **Валидатор:** Tier A (SPARK On, если на Ada), проверяет schema перед применением.

#### 4.2.6. Merkle tree / HMAC audit log
Продолжение H61 (HMAC на superblock — решён в v0.34; ключ детерминированный, RDRAND → Блок 3).
- **Что даёт:** proof-of-inclusion (доказать, что событие X было в логе, не отдавая весь лог). Tamper-evident: подмена блока ломает корень.
- **Ограничение:** без HWRoT (TPM) это **detect, не prevent**. P4 с физическим доступом подменяет весь лог + пересчитывает корень. Merkle tree помогает только если root hash сохранён в write-once область (NVMe write-once, или boot counter region).
- **Формулировка в claim:** «tamper-evident при условии доверенного root hash; без HWRoT — integrity, не attestation».
- **Зависимость:** H61 (HMAC key placement) — ✅ решён (Tier B, ключ в superblock; защита от P3, не от P2).

#### 4.2.7. Measured boot (опционально remote attestation с TPM)
- **Measured boot:** хэши доменов в boot counter region (write-once). Проверяются при следующем boot. **Detect, не attest.**
- **Remote attestation:** требует TPM quote (удалённая сторона проверяет, что хэши получены от доверенного корня). T580 — проверить fTPM. Pi 4 — нет.
- **Без HWRoT:** не заявлять как attestation. Записать в THREAT_MODEL §8 как R16 (уже есть).

### 4.3 Threat model updates

Новые строки в THREAT_MODEL.md §12.12 (T17–T20, R19–R20):
- **T17** VMM compromise (virtio bug) → контроль над гостем, containment защищает ядро. Гость — Tier C (untrusted).
- **T18** Guest → host log injection (stdout в audit log). Fix: префикс + валидация.
- **T19** YAML capability escalation. Fix: schema-валидатор (Tier A).
- **T20** «Attestation» без HWRoT = measured boot, не remote attestation. Не заявлять шире.
- **R19** VMM в shared image без H87 → OOB в `.bss`. Предпосылка P1.
- **R20** MCS Dashboard через tracing kernel → не-verified config, claim ломается. Fix: manual accounting.

### 4.4 Что НЕ делать в этом векторе

- Не начинать до H87/Точки С (P1/P3).
- Не заявлять remote attestation без TPM.
- Не использовать tracing kernel для MCS Dashboard (claim ломается).
- Не делать YAML без schema-валидатора (T19).
- Не выносить VMM в Ring 0 (VMM — Tier B, не TCB).

### Референсы (брать принципы, адаптировать)

| Проект | Что | Роль для нас |
|---|---|---|
| **Makatea** (UNSW TS) | Qubes-подобная ОС поверх seL4 (замена Xen) | главный архитектурный референс |
| **Kry10 OS** | коммерческая ОС на seL4, сложные нагрузки | валидация «seL4 может это» |
| **Qubes OS** | индустриальный стандарт изоляции | сценарии и модель изоляции |
| **seL4 Microkit / CAmkES VM** | готовые блоки VMM/VM на seL4 | стартовая точка, не изобретать VMM с нуля |

### Метка

`[позже]` — начинать **после Точки С** (готовый TCB) и после H87. Не блокирует Б→С.
