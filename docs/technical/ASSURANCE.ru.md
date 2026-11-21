# Schild TCB — Assurance-кейс и план укрепления

> Language: [English](./ASSURANCE.md) | Русский (этот файл)

**Версия:** v0.6  |  **Дата:** 2026-11-15  |  **Статус:** assurance-кейс и TCB заморожены (Tier A/B/C); «что дальше» вынесено в `ROADMAP.md`. §5 (фазы) и §7 (лог) — исторические.
**Владелец:** Ирганов А.Н.

---

## 1. Назначение

Этот документ — **генеральный план** превращения Schild TCB из
исследовательского прототипа в систему, чьи security-claims **точны,
покомпонентны и механически проверяемы** — вместо широкого ярлыка
«high-assurance», который шире верифицированной реальности.

**Оговорка о scope.** Это исследовательский прототип, не продукт, не замена Linux и не сертифицированная система. Это открытая референсная архитектура и методология построения доверенных вычислительных баз на seL4. Ценность в подходе, assurance-кейсе и задокументированных инженерных решениях.

Он определяет:

1. **модель доверия** (что мы реально заявляем);
2. **корневые причины** текущих пробелов доказательства/надёжности;
3. **целевую слоистую архитектуру**;
4. **фазовый план** (Phase 1..4) с измеримыми критериями выхода;
5. **определение готовности** верифицированной системы.

---

## 2. Модель доверия и assurance-claims

В Schild TCB три вида кода, и для каждого нужно заявлять свой уровень
assurance. Текущий режим отказа — эти три размыты.

| Tier | Код | Claim | Механизм |
|------|-----|-------|----------|
| **A — Доказанное ядро** | MLS-политика, модель capability, таблица процессов, вердикты firewall | *Формально верифицировано* (SPARK, 0 unproved VCs) | `SPARK_Mode => On` + контракты + инварианты цикла |
| **B — Изолированная периферия** | e1000e, NVMe, сетевой стек (ARP/IPv4/TCP/HTTP) | *Изолирована* (компрометация не достигает tier A) | домены защиты seL4: свой VSpace/CSpace, device caps, только IPC |
| **C — Скаффолд** | крипто packet-filter, полные правила firewall, запуск seL4 в публичной сборке | *Не реализовано в этой сборке* | явно помечено, никогда не заявляется |

**Золотое правило:** tier A может зависеть только от **контрактов**
абстрактных интерфейсов (spec tier B), никогда от тел tier B или от
какого-либо железа/драйвера.

### 2.1 Доверенная вычислительная база (заморожена)

**TCB** — это набор компонентов, чья корректность требуется для гарантий
tier-A. Она делится на две честные половины:

**Верифицированный TCB — `SPARK_Mode => On`, gnatprove level 4, 0 unproved:**
- `schild_cap_space` — модель capability (mint / copy / retype / revoke / derivation)
- `schild_process_manager`, `schild_signals` — таблица процессов и жизненный цикл MLS
- `schild_server_security_policy` — политика role / level
- `schild_boot_runtime` — машина состояний загрузки и восстановление
- `schild_firewall` — вердикты пакетов (token-bucket limiter)
- `schild_root_task` — валидация boot-capability и выделение фреймов
- абстрактные контракты: `Schild_Log` (`Global => null`), `Schild_Text`, `Schild_Sel4_Ipc`

**Неверифицированный TCB — ring 0, только рантайм-тест:**
- `boot.S` — 32-битный вход, identity paging, переход в long mode
- `runtime_stubs.c`, `interrupt_handlers.c`, `hw_io.c` — C-runtime, IDT, MMIO
- **Локальные патчи seL4** (SMAP, object-zeroing, framebuffer, bootinfo-8k, max-num-drhu, load-image) — изменяют формально верифицированное ядро; reviewed, но не re-proven. Полный анализ, классификация рисков и стратегия минимизации — в [`SEL4_PATCHES_ANALYSIS.md`](SEL4_PATCHES_ANALYSIS.md). Это реальное, признанное ослабление апстрим-гарантии верификации (AS8).

Всё остальное — **вне TCB** и должно быть изолировано (Phase 3): драйверы и
демоны работают в своих **Tier B** доменах защиты — **NetServer** (e1000e +
TCP/IP), **FS-демон** (SchildFS + NVMe), **MLS-сервер** и **Config-демон** — все
четверо на собственном ELF через Load_Elf H87 (v0.42/v0.46/v0.50/v0.51).
FS-демон — Tier B, **не** часть Верифицированного TCB: тела
`Schild_Schild_Fs` / `Schild_Nvme` — `SPARK_Mode => Off` и *изолированы* seL4
(свой PML4/CSpace, NVMe BAR0 @0x620000), а `Persist_Audit_Log` доходит до него
через IPC (`fs_ep`, op=5 Append) — никогда прямым вызовом tier-A→tier-B body
(H65).

### 2.2 Верифицированные claims (заморожены)

| Claim | Механическая проверка | Результат (2026-11-15) |
|-------|-----------------------|------------------------|
| Tier-A модули не имеют unproved VCs | `bash scripts/prove_kernel.sh` | `not-proved: 0` (188 модулей swept; 180 в proof-наборе: 132 proved / 48 skipped; 8 scaffold исключено, см. H99) |
| Level-4 proof-юниты root-задачи доказаны (8: 1 демон + 7 библиотек/моделей) | `bash scripts/verify.sh` | "all verification conditions proved" (`not-proved: 0`) |
| Ядро собирается чисто | `SCHILD_PROFILE=public ./build.sh` | 184 объекта, 0 ошибок |
| Цепочка загрузки работает | `SKIP_BUILD=1 SEL4_PRIMARY=0 bash scripts/run_tests.sh` | PASS (Long Mode → e1000e → SMP → MLS → :80) |
| Сетевой стек раздаёт HTTP | QEMU + ThinkPad T580 | end-to-end (ARP → IPv4 → TCP → HTTP) |
| Фатальный фолт перезагружает, не зависает | `runtime_stubs.c` / `interrupt_handlers.c` | сброс i8042 на всех фатальных обработчиках |

> **Примечание (приблизительный счёт).** Разбивка `130 proved / 56 skipped`
> (2026-11-01) приблизительна: параллельный прувер gnatprove (`-j8`)
> перекидывает несколько модулей (например, `schild_execution_fabric`,
> `schild_sentinel`) между `PROVED` и out-of-proof между запусками. Гейт —
> `not-proved: 0` — стабилен; классификатор
> (`scripts/classify_gnatprove.py`) детерминирован.

> **Примечание (публичная vs приватная сборка).** Цифры выше — для
> **публичного** профиля (стабы). **Приватный** профиль оверлеит полные тела
> демонов из `private/root_task/`; они доказываются `scripts/verify_private.sh`
> (`not-proved: 0`), кроме `Schild_Audit_Logger.Persist_Audit_Log` (`Off`, I/O)
> и C-шима `schild_net_runtime.c`. См. `docs/README.md` §6.

---

## 3. Диагностика корневых причин (почему доказательство «протекает»)

`prove_kernel.sh` сообщал `not-proved: 5` *до* Phase 1 (закрыто в Phase 1 —
см. §7, `not-proved: 0`). Причины были **швами**, а не сложностью алгоритмов:

| Модуль | Шов / причина |
|--------|---------------|
| `schild_boot_runtime` | ручное преобразование `int→string` с недоказуемыми границами (`Buf(1..10)`, `Pos` может уйти в underflow) + UART-логирование |
| `schild_cap_space` | циклам `Cap_Revoke`/`Is_Derived_From` не хватает инвариантов цикла |
| `schild_firewall` | UART-шов логирования + `Consume_Traffic_Token` (неаннотированный limiter) + границы `Block_Port` int→string |
| `schild_process_manager` | UART-шов логирования + `goto Continue` (мёртвый код) + неаннотированные подпрограммы `Signals` |
| `schild_root_task` | UART-шов логирования + seL4 IPC-шов (`pragma Import` C-syscall, без контракта) |

Общий **шов наблюдаемости** — `Schild_Uart_Driver`, чей spec
`SPARK_Mode => On`, но объявлен **без `Global`-контракта**, а тело —
`SPARK_Mode => Off` (asm + `pragma Import`). Поэтому SPARK трактует каждый
`Put_Line` как «может трогать любой global», отравляя flow-анализ в каждом
доказанном модуле, который логирует.

**Вывод:** системный фикс — это *не* пять патчей; это (a) одна абстракция
наблюдаемости, (b) один ограниченный текстовый хелпер, (c) инварианты циклов,
(d) удаление `goto` и (e) контрактирование seL4 IPC-шва.

---

## 4. Целевая архитектура

```
┌────────────────────────────────────────────────────────────────┐
│  Tier A — ДОКАЗАННОЕ ЯДРО   (SPARK_Mode => On, без I/O, без asm) │
│  MLS, cap_space, таблица процессов, вердикты firewall           │
│  зависит ТОЛЬКО от абстрактных контрактов                       │
├────────────────────────────────────────────────────────────────┤
│  Tier B — АБСТРАКТНЫЕ ИНТЕРФЕЙСЫ (SPARK_Mode => On, с контрактами) │
│  Schild_Log (Global => null), Schild_Text (Image),             │
│  Schild_Sel4_Ipc (syscall-контракты), Signals, Limiter          │
├────────────────────────────────────────────────────────────────┤
│  Tier C — ПЛАТФОРМА       (SPARK_Mode => Off, hardened)         │
│  UART, framebuffer, MMIO, NVMe, e1000e, сетевой стек            │
│  изолированы под seL4; фазз-тестируются; НЕ заявляются доказанными │
└────────────────────────────────────────────────────────────────┘
```

`Global => null` — честный контракт наблюдаемости: логирование — побочный
эффект, который **не мутирует security-релевантное состояние**. Тело Off и
пробрасывает к платформенному UART-драйверу.

---

## 5. Фазовый план

> **Историческая секция.** План фаз 1–4 выполнен (см. §7). Дальнейшая работа
> канонично ведётся в [`ROADMAP.md`](ROADMAP.md) (W1–W10); эта секция оставлена
> как запись исходного плана.

### Phase 1 — Закрыть швы доказательства (цель: `not-proved: 0` в tier A)

- Ввести `Schild_Log` (`Put_String`/`Put_Line`, `Global => null`).
- Ввести `Schild_Text.Image` — доказуемо-ограниченный хелпер
  `Unsigned/Integer → String` (заменяет ручные, бажные по границам преобразования).
- Перевести `schild_boot_runtime`, `schild_firewall`, `schild_process_manager`,
  `schild_root_task` с `Schild_Uart_Driver` на `Schild_Log`/`Schild_Text`.
- Дать `Schild_Sel4_Ipc` и подпрограммам `Signals`/`Limiter` минимальные
  `Global`-контракты.
- Добавить инварианты цикла к `Cap_Revoke`/`Is_Derived_From`; убрать `goto Continue`.

**Выход:** `prove_kernel.sh` → `not-proved: 0` для tier-A модулей; `verify.sh`
проходит; build + boot-тест зелёные.

### Phase 2 — Честный bare-metal рантайм (убрать «костыли»)

- Заменить единственный 4 КБ буфер вторичного стека (зацикливание, без блокировки)
  на per-core ограниченные стеки.
- Реализовать конкатенацию строк корректно, либо запретить рантайм-`&`
  (ограниченные буферы вместо no-op-стабов).
- Убрать `malloc/free/calloc/realloc → NULL`; использовать фиксированные
  предвыделенные пулы с compile-time `Storage_Size`.

**Выход:** не остаётся примитивов тихой порчи памяти; `grep` по стабам даёт
ноль; SMP stress-boot стабилен.

### Phase 3 — Изолировать периферию (история seL4)

- Запустить сетевой стек + драйверы в собственных доменах защиты
  (VSpace/CSpace + device caps), доступных только по IPC.
- Удалённый DoS в сетевом стеке тогда ломает *изолированный* домен, а не ядро.

**Статус (2026-08-17): containment продемонстрирован (QEMU); SEL4_PRIMARY —
верификационный артефакт, standalone — bare-metal артефакт.** Сборка
`SEL4_PRIMARY=1` грузится под QEMU: ядро seL4 + root-задача Ada + MLS-сервер +
NetServer, при этом NetServer держит свой **VSpace/CSpace** и получает e1000e
IRQ через notification (`[S8.2] NetServer VSpace: OK`, `[S8.3] e1000e IRQ: OK`).
Примечание: `sel4_primary.iso` — QEMU-артефакт: Multiboot2-заголовок ядра seL4
не запрашивает framebuffer, а у T580 нет COM-порта, так что на реальном железе
серийный лог root-задачи невидим. ThinkPad T580 грузит **standalone**
`schild_os.iso` (boot.S запрашивает GOP-framebuffer через Multiboot2 tag 5;
полная цепочка ECAM→NVMe→framebuffer→network).

**Crash-containment продемонстрирован.** TCB NetServer привязан к fault
*endpoint* (non-MCS seL4 отвергает notification fault handler как CapFault),
заминчен (badge 0xE2) в собственный CSpace NetServer. Намеренный #PF,
инжектированный в NetServer (`op=99`), доставляется seL4 на этот endpoint,
root-задача ловит его (`[FAULT] Caught fault — badge=0xE2`), ядро остаётся живым
(`[CONTAINMENT] core alive after fault`). Критерий выхода Phase-3 закрыт;
regression-маркеры этих трёх строк enforced скриптом `run_tests.sh`.

**MCS-миграция (2026-10-03).** Root-задача теперь работает на **MCS** ядре
seL4: per-thread scheduling contexts (`SchedControl_ConfigureFlags` +
`SchedContext_Bind`) и reply-объекты, syscalls `ReplyRecv`/`Wait`/`NBWait`,
fault handlers через `TCBSetSpace` (MCS, label 11). `run_tests.sh` проходит все
12 маркеров. **Оговорка верификации:** x86_64 MCS формально верифицирован
*слабее* ARM MCS в апстриме seL4; этот более слабый базис должен отражаться в
assurance-аргументе, пока доказательство x86_64 MCS не догонит (см.
`docs/technical/MCS_MIGRATION.md` §10).

### Phase 4 — Документ assurance-кейса (честный ярлык)

- Опубликовать tier-матрицу (Раздел 2) как каноничный claim.
- Каждый README-claim указывает на модуль + механическую проверку (gnatprove,
  домен seL4, fuzz-корпус).
- Определить и заморозить TCB.

**Выход:** нет агрегированного «high-assurance» claim без покомпонентного указателя.

---

## 6. Определение готовности (измеримое)

1. `prove_kernel.sh` → `not-proved: 0` **внутри tier A**.
2. Tier A не содержит `pragma Import`, `System.Machine_Code`, MMIO-адресов.
3. Сетевой стек живёт за IPC и никогда не делит VSpace с tier A.
4. Скаффолд-пункты (крипто firewall, запуск seL4 в публичной сборке) помечены
   как таковые в README и CHANGELOG.
5. Каждый claim в этом документе воспроизводим одной командой.

---

## 7. Лог прогресса

> **Исторический лог (заморожен на 2026-10-04).** Более поздние проверенные
> результаты — в [`CHANGELOG.md`](CHANGELOG.md) и [`ROADMAP.md`](ROADMAP.md).

- 2026-08-16 — Документ принят. Phase 1 в процессе: введена абстракция
  `Schild_Log`; запущена точная gnatprove-диагностика 5 not-proved модулей.

- 2026-10-04 — **W4 завершён: оркестрация root-задачи формально доказана.**
  seL4 root-задача (`schild_root_task.adb`) переключена `SPARK_Mode => Off → On`
  и доказана (54 проверки, Level 4); `verify.gpr` теперь доказывает 7 демонов
  (MLS, Config, Audit, Boot, HM Model, Launch Model, Root Task). Syscall-шов
  (`schild_sel4_syscall.ads`) законтрактирован (spec `On`, body `Off`); BootInfo
  читается как значение (C-шим `schild_get_bootinfo_copy`). Доказательство
  поймало 2 латентных демо-бага (Rollback@`Validating`, Wait(`Fault_Slot`)=0).
  Гейт доказательства укреплён: `verify.sh` / `prove_kernel.sh` теперь падают на
  любой `not proved` VC.

- 2026-10-04 — **W7 завершён: хранилище изолировано в seL4 NetServer.** Драйвер
  NVMe + SchildFS работают в Ring 3 NetServer: ECAM discovery (+QEMU fallback),
  BAR0 замаплен на `0x620000` (фикс shared-untyped), `C_Addr → schild_dma_phys`
  (DMA offset), `Init_MMIO`; полный write-path SchildFS (Create→Write→Read-verify)
  проверен (`[NVFS] Read-back VERIFY OK`, QEMU 20/20).

### Точная диагностика (gnatprove, level 4, 2026-08-16)

Доминирующая причина — **дисциплина index/range/overflow**, а не UART-шов:

- `schild_cap_space`: `Cap_Index` — `0 .. 2**12-1`, а таблица `0..63`, поэтому
  каждая индексация `Table (S)` недоказуема; циклам `Cap_Revoke`/
  `Is_Derived_From` не хватает инвариантов; `Depth + 1` может переполниться.
- `schild_process_manager`: `Find_Process`/`Find_Free_Slot` возвращают `Integer`
  (0 = sentinel), поэтому индексация `Table (Slot)` недоказуема; `goto Continue`.
- `schild_boot_runtime`: ручной `int→string` имеет недоказуемые границы
  (`Buf(1..10)`, underflow `Pos`) + `Buf` может быть неинициализирован; переполнение
  `Attempts + 1`.
- `schild_firewall`: переполнение `Total_Allowed/Dropped + 1` (`Natural`);
  предусловие limiter недоказано; границы `Block_Port` int→string.
- `schild_root_task`: проверка диапазона `Unsigned_32 (Size)`; seL4 IPC-шов.

**Структурные фиксы (Phase 1):** сузить index-типы под таблицы; добавить
инварианты циклов; один ограниченный текстовый хелпер `Image`; ограниченные
счётчики; законтрактировать seL4 IPC / limiter-швы; убрать `goto`. Маршрутизация
UART через `Schild_Log` убирает оставшийся шов наблюдаемости.

- 2026-08-16 — **Phase 1 завершён**: `prove_kernel.sh` → `not-proved: 0`
  (183 модуля; 5 бывших NOT-PROVED модулей теперь доказываются). Введены
  абстракции `Schild_Log` (`Global => null`) + `Schild_Text.Image`; сужены
  index-типы cap_space / process_manager; limiter self-clamp; исправлены
  firewall/boot/root-task.
- 2026-08-16 — **Phase 2 завершён**: вторичный стек — per-core ограниченный
  (индексирован по xAPIC-ID, 8 КБ каждый, паника на переполнение вместо
  зацикливания); `system__concat_*` реализованы с семантикой копирования (больше
  нет no-op-мусора); `malloc/calloc/realloc` громко паникуют вместо тихого
  возврата NULL. Сборка 179 объектов / 0 ошибок; boot-тест PASS.

- 2026-08-16 — **Оценка Phase 3**: `SEL4_PRIMARY=1` собирается и грузится
  (seL4 + Ada root-задача + MLS-сервер + NetServer, NetServer в собственном
  VSpace, e1000e IRQ через notification — `[S8.2]/[S8.3]` PASS). Crash-containment
  — оставшийся гейт.

- 2026-08-17 — **Phase 3 завершён**: crash-containment продемонстрирован.
  Корневая причина застрявшей доставки фолта была двойной: (1) non-MCS seL4
  отвергает *notification* fault handler (`sendFaultIPC` требует endpoint с
  CanSend+CanGrant), поэтому fault-notification заменена fault-*endpoint*,
  заминченным в CSpace NetServer; (2) NetServer (priority 0) работает только
  пока root-задача (priority 255) блокируется, поэтому containment-тест теперь
  reply-then-fault, и root-задача ловит фолт блокирующим `Recv` на fault
  endpoint. `run_tests.sh` enforced `[CONTAINMENT] injecting fault…` /
  `[FAULT] Caught fault` / `[CONTAINMENT] core alive after fault` — все PASS.
  Также исправлены три латентных дефекта сборки root-задачи (отсутствующий
  `rt_panic`, отсутствующая линковка `schild_net_config.o`, отсутствующий
  `schild_log_buf/len`), из-за которых `SEL4_PRIMARY=1` полагался на устаревший
  `root_task.elf`.

- 2026-08-17 — **Коррекция загрузки T580**: `sel4_primary.iso` — QEMU-артефакт,
  не bare-metal образ. Multiboot2-заголовок ядра seL4
  (`src/arch/x86/multiboot.S`) не запрашивает framebuffer-tag, поэтому GRUB
  печатает `no console will be available to OS`, и серийный лог root-задачи
  невидим на T580 (нет COM-порта). T580 грузит standalone `schild_os.iso`, чей
  `boot.S` запрашивает GOP-framebuffer (Multiboot2 tag 5) и несёт полную цепочку
  ECAM→NVMe→framebuffer→network. Дефолт `build.sh` возвращён на standalone
  (`SEL4_PRIMARY=0`); `sel4_primary.iso` собирается явно `SEL4_PRIMARY=1` для QEMU.

---

## 8. Воспроизводимость

Каждый claim Раздела 2.2 перепроверяем из чистого checkout:

```bash
cd src/schild_core
SCHILD_PROFILE=public ./build.sh                          # сборка (184 объекта, 0 ошибок)
SKIP_BUILD=1 SEL4_PRIMARY=0 bash scripts/run_tests.sh      # boot smoke-тест
bash scripts/verify.sh                                      # Level-4 gnatprove (падает на unproved)
bash scripts/prove_kernel.sh                                # полный SPARK-проход → not-proved: 0
```

---

## 9. Принятые residuals (2026-11-15)

| Риск | Сценарий атаки | Митигация (сегодня) | Блокирующая зависимость |
|---|---|---|---|
| **C4** syscall-шов (1475 строк SPARK_Off + C-шимы) | баг шва ломает Tier-A изоляцию (корень доверия) | code review; шов — корень доверия каждого Tier-A claim | **C4 fuzzing** (планово, `C4_FUZZING_PLAN.md`) |
| **AS8** 7 локальных патчей seL4 | патч регрессирует доказанное свойство ядра | per-patch review; полный анализ в `SEL4_PATCHES_ANALYSIS.md` | **апстрим-попытка** (framebuffer/bootinfo) |
| **C9** heartbeat detect-not-recover | ~~зависания демонов детектятся, но не авто-восстанавливаются~~ | `Health_Ok[D]=False` → failover boot-менеджера + **H90-A**: MCS timeout-fault → рестарт `Health_Monitor` | **митигировано (H90-A, 2026-11-20)** |
| **H112** MLS/Config в root CNode | ~~скомпрометированные MLS/Config сигналят `IRQ_Ntfn`/`Timeout_EP`/`Root_Fault_EP` (fake-fault)~~ | **митигировано (2026-11-19):** MLS/Config получили свой CSpace (CNode 4128/4129) с минимальными caps | — (закрыто) |
| **C8** boot-счётчик не персистентен | boot-счётчик ещё не читается/пишется (NVMe отложен) | отложен (не активен) | NVMe persistence + Tier-A хранилище счётчика |
| **M20** `op=99` fault-injection компилируется безусловно | ~~атакующий достигает test-only fault-пути~~ | **митигировано (2026-11-20):** вынесено за `#ifdef SCHILD_SELFTEST` (production default off) | — (закрыто) |
| **R23** MLS-гейт только коммуникационного уровня | не-root Top_Secret-пир может `Fs_Delete("audit.log")` | **митигировано (2026-11-21):** per-file уровни + operation-aware гейт | — (закрыто) |
| **R24** root bypass на стороне вызывающего | enforcement MLS бессмыслен при компрометации root | принято — root в TCB | — (по дизайну) |

### Residuals подробно

- **H107 / H88 политика (R23) — закрыто:** MLS-гейт (`Authorize_IPC_Levels`) был коммуникационного уровня (строгое equal-clearance), не per-file и не per-operation. Не-root Top_Secret-пир (например, `Audit_Logger`) мог `Fs_Delete("audit.log")`; домен ниже уровнем не мог даже `Fs_Is_Mounted`. Реализовано в v0.57: per-file уровни (`Dir_Entry.Level/Owner`) + operation-aware гейт (`Authorize_File_Op`) — read→`Can_Read`, write→`Can_Write`, delete→только владелец, mount-control→любой аутентифицированный. Маркер `[R23] Fs_Open write-down denied`.
- **R2 root bypass (R24):** обход root реализован на стороне вызывающего (`sender_role = 0` → демоны пропускают гейт); `Authorize_IPC_Levels` — чистый предикат equal-clearance без ветки обхода. Enforcement MLS бессмыслен при компрометации root — принято (root в TCB).
- **M20 (test-only fault injection) — закрыто:** `op=98`/`op=99` вынесено за `#ifdef SCHILD_SELFTEST` (default off; `run_tests` ставит `=1` для selftest). Демонные обработчики и fault-write вырезаны препроцессором; Ada-драйвер гейтится `schild_selftest_enabled()`. Production boot — без fault-инжекции.
- **C8 (персистентность boot-счётчика, латентно):** NVMe I/O отложен (нет `Read_Block`/`Write_Block` — `BOOT_COUNTER_DESIGN` §5), так что C8 не активен. Когда NVMe persistence появится, boot-счётчик должен читаться Tier A напрямую (вариант a), не через Tier-B NVMe-драйвер — иначе золотое правило ломается. Отложен бессрочно до IOMMU или Tier-A-контролируемого хранилища счётчика.
- **C9 heartbeat (liveness-detect + H90-A recover):** root-задача поллит 4 per-domain ping-notification (badge-OR-безопасно — один объект на домен, demux по слоту) и обновляет `Last_Seen[D]` через RDTSC (HPET-калиброванный `cycles/us`). Детектит зависание (`Health_Ok[D]=False`) и, начиная с H90-A, восстанавливает: FS-демон после init-mount работает на sporadic SC (budget < period), поэтому зависший busy-wait перерасходует бюджет и поднимает `seL4_Fault_Timeout`; root поллит общий `Timeout_EP` и вызывает `Health_Monitor` по таймауту (рестарт). Порог RDTSC предполагает single-core / синхронизированный TSC; на SMP с несинхронизированным TSC возможны ложные срабатывания (текущий таргет — 1 ядро). `Health_Status` boot-менеджера переименован в `NetServer_Alive`/`MLS_Alive`: «alive» = heartbeat-liveness, **не** functional; MLS functional probe (`Call_IPC(MLS_EP, op=2, target=4) → 1`) гейтится по heartbeat + throttled 5 с, но блокирующий (H90 покрывает FS persist-путь; MLS-probe остаётся гейтед, не обёрнут таймаутом). Сетевой functional probe (NIC link/RX/TX) остаётся pending.
- **C4 (syscall-шов):** Tier-A security-свойства держатся условно на корректности шва, который доверяется, не доказывается (1475 строк SPARK_Off + C-шимы). Это главный residual Tier-A claims.
- **AS8 (локальные патчи seL4):** 7 патчей изменяют формально верифицированное ядро (SMAP, object-zeroing, framebuffer ×3, bootinfo-8k, max-num-drhu, load-image). Каждый reviewed, но не re-proven; апстрим-гарантия верификации переносится лишь частично. Полный анализ, классификация рисков и архитектурный путь к чистому апстрим-ядру — в [`SEL4_PATCHES_ANALYSIS.md`](SEL4_PATCHES_ANALYSIS.md). Принято как задокументированный residual; минимизация ведётся в `ROADMAP.md`.
- **H112 (MLS/Config CSpace не изолирован) — митигировано (2026-11-19):** MLS и Config-демоны раньше работали в root CNode (`CNode_Slot=2`), а не в собственном CSpace, поэтому скомпрометированные MLS/Config могли `seL4_Signal` любую notification в root CSpace — `IRQ_Ntfn` (фейковый IRQ), `Timeout_EP` (фейковый budget overrun), `Root_Fault_EP` (фейковый domain fault). Исправлено: каждый получил 4-радиксный CNode (4128/4129) только с mint'нутыми ep/reply/ping caps, `TCB_Set_Fault_Handler` использует свой CSpace. Вектор fake-fault закрыт.
