# Schild TCB — Анализ патчей seL4 и стратегий минимизации

**Дата:** 2026-11-10
**Статус:** информационный документ, решения не приняты
**Scope:** все модификации seL4 в Schild TCB, их назначение, риски, альтернативы, актуальные данные из первоисточников
**Связанные документы:** `THREAT_MODEL.md` §9; `START/PATCHES_CRYPTO_PLAN.md`, `START/HANDOFF.md`, `START/AUDIT_REGISTRY.md` (локальный handoff-каталог, gitignored)

## 1. Назначение

Зафиксировать полную картину модификаций `seL4` в Schild TCB: зачем каждая, что она меняет в verified-ядре, какие есть альтернативы и как двигаться к минимизации патчей или к чистому upstream-ядру. Документ — только для сбора информации; решения по удалению или замене патчей принимаются отдельно.

## 2. Контекст: почему патчи вообще есть

`seL4` — формально верифицированное микроядро. Любой патч в коде ядра выводит соответствующую часть из-под доказательства. В `PATCHES_CRYPTO_PLAN.md` уже зафиксирован честный принцип: патчи «self-reviewed by author, not independently reviewed, not re-proven». Это правильная формулировка, но она же задаёт и цель: сократить число таких «trusted-but-not-re-proven» участков.

Официальные verification assumptions `seL4` (`sel4.systems/Verification/assumptions.html`) прямо перечисляют, что proofs **не** покрывают:

- boot code (включая `load-image`, размещение модулей, `MAX_NUM_DRHU`);
- cache maintenance (включая SMAP-путь);
- context switch для системных регистров;
- device address translation (DMA, IOMMU).

Это значит, что часть наших патчей лежит в зоне, которая **и так вне scope proof**. Это не оправдывает патчи, но объясняет, почему upstream сам периодически аудирует и правит этот код (см. §4).

## 3. Текущее состояние: 7 патчей

Классификация по трём осям: (а) без патча система не загрузится; (б) патч можно вывести из security TCB; (в) патч под конкретную платформу.

### Класс 1. Без патча система не загрузится

#### 1.1. `max-num-drhu.patch`

**Назначение.** Уменьшает `.boot.bss` ядра, чтобы GRUB не загружал boot-модуль (root task) в зону, которую ядро затем обнуляет (`memzero`) при инициализации.

**Что ломается без него.** Эксперимент 2026-11-09 (`HANDOFF.md`, «эксперимент с DRHU-патчем»): без патча `.boot.bss` вырастает до 8 MB, `module #0` попадает в `0x71a000`, внутри kernel region `0x100000..0xa21000`. `load-image` копирует модуль выше, но source уже затёрт `memzero`. Результат: `run_tests` FAIL, 870 IRQ от e1000e, система висит. Патч не аннулируется.

**Риск.** Меняет размер статической структуры `drhu_list[MAX_NUM_DRHU]` в boot-коде. Это не verified-часть, но код, который исполняется до того, как доказательства вступают в силу. Если патч ошибочен, ядро может не дойти до verified-состояния.

**Альтернативы.**
- **Долгосрочная:** root task как ELF-child (`Load_Elf` после kernel boot), а не GRUB-module. Тогда GRUB грузит только kernel, модули в userspace, и `load-image`/DRHU-конфликт исчезает архитектурно. В `HANDOFF.md` это записано как «Блок 3, L».
- **Среднесрочная:** проверить, можно ли поднять `MAX_NUM_DRHU` не через патч, а через конфигурацию `seL4`. Сейчас параметр жёстко зашит в `boot_sys.h`; в upstream PR #721 (`CONFIG_MAX_NUM_BOOTINFO_UNTYPED_CAPS`) видно, что upstream движется в сторону конфигурируемости, но `MAX_NUM_DRHU` пока не в этом списке.

#### 1.2. `smap.patch`

**Назначение.** Включает SMAP (Supervisor Mode Access Prevention) при `CONFIG_PRINTING=1`.

**Что ломается без него.** Эксперимент 2026-11-09 («SMAP-патч, отрицательный результат»): при `CONFIG_PRINTING=0` и upstream-условии `!PRINTING && !DANGEROUS` SMAP включается, но `serial_init` в `seL4` зависит от `CONFIG_PRINTING`. Без PRINTING UART не инициализируется, `DebugPutChar` не работает, serial log пуст. Observability теряется полностью. Патч не аннулируется.

**Риск.** SMAP — аппаратная защита, но патч меняет условие её включения. Если патч ошибочен, SMAP может быть выключен там, где предполагался включённым.

**Альтернативы.**
- **Проверить upstream.** В `seL4` 16.0.0 и 17.0.0 ведутся работы по unverified-конфигурациям, но развязки SMAP и PRINTING в CHANGES.md не найдено. Нужно проверять каждый релиз.
- **Отказаться от `DebugPutChar` как единственного канала observability.** Если root task пишет лог не через `seL4_DebugPutChar`, а через собственный драйвер UART (как в bare-metal образе), зависимость от `CONFIG_PRINTING` снимается, и SMAP-патч становится ненужным. Это архитектурная правка, не патч ядра.

### Класс 2. Патчи, которые можно вывести из security TCB

#### 2.1. `object-zeroing.patch`

**Назначение.** Возвращает `memzero` для TCB/Endpoint/Notification в `createObject`, потому что upstream `seL4` перестал это делать (перенёс zeroing в `resetUntypedCap`).

**Что ломается без него.** Upstream HEAD (`c98d70a`) не содержит `memzero` в `createObject` для этих типов. Если патч убрать, объекты могут содержать данные предыдущего использования. Это не «система не загрузится», но это ослабление изоляции.

**Риск.** Патч добавляет `memzero` в путь создания объектов. Если upstream уже делает zeroing на уровне `resetUntypedCap`, патч может быть избыточным (двойной zeroing).

**Альтернативы.**
- **Проверить, покрывает ли `resetUntypedCap` все случаи.** Upstream commit `03c71b6` делает retype-путь ответственным за zeroing: «The Retype operation now zeroes the entire range of the Untyped cap … before installing any objects. The initial zeroing phase is preemptible». Более поздний коммит `41a13993` (#958) удаляет `memzero` из `createObject` для `SchedContextObject` и `ReplyObject`, потому что «memory is now cleared via `clearMemory` within `resetUntypedCap`».
- **Если upstream не покрывает какой-то тип,** заменить патч на runtime-проверку в root task: после создания объекта записать в него известный паттерн и проверить, что он читается. Это не докажет zeroing, но даст runtime-детект.

**Проверка 2026-11-10 — confirmed: патч избыточен.**

Аудит `schild_sel4_syscall.adb` показал:

- все объекты ядра (`TCB`, `Endpoint`, `Notification`, `CNode`, `SchedContext`, `Reply`, `PML4`, `PDPT`, `PageDirectory`, `PageTable`, `Frame` для IPC/shared/образов) создаются только из RAM-untyped (`UT1..UT6`, `UT_SC`, `UT_Reply`, `UT_EP`, `UT_TCB`, `UT_IPC`, `UT_CN`, `UT_ELF`, `RAM_UT`), фильтр `Is_Device = 0` (строки 951, 1652);
- `Dev_UT` (`Is_Device = 1`) используется только для `Object_LargePage` (ECAM, строка 809) и `Object_Frame` (MMIO NIC/NVMe, строки 1045, 1587); ни один объект ядра из device untyped не создаётся;
- upstream `03c71b6` обнуляет всю RAM-область при первом `retype` (preemptible), `41a13993` удаляет дублирующий `memzero` из `createObject`.

Вывод: патч `object-zeroing` делает то же, что upstream, но в `createObject` — коде, покрытом refinement proof. Удаление патча уменьшает verified surface (единственный патч, который трогает `createObject`), не ослабляя безопасность. Device untyped не обнуляется upstream, но Schild TCB не создаёт из него объектов ядра, только MMIO-страницы, где утечка данных не применима.

#### 2.2. `framebuffer.patch` (x3)

**Назначение.** Отображение boot-консоли на framebuffer (T580 без serial-порта).

**Риск.** По `PATCHES_CRYPTO_PLAN.md` §1: framebuffer использует `paddr_to_pptr(boot_state.fb_info.addr)`, нового mapping нет, assert `kernel_window_used + fb_size <= ...` не нужен. Это cosmetic-патч, не security-relevant.

**Альтернативы.**
- **Вывести из security TCB.** Уже сделано в плане: «Framebuffer display-only (вывести из security TCB)». Патч остаётся, но не считается частью trust surface.
- **Убрать совсем,** если root task будет рисовать консоль сам (через собственный framebuffer-драйвер). Это L-работа, но она убирает патч из ядра.

### Класс 3. Патчи под конкретную платформу

#### 3.1. `bootinfo-8k-untyped.patch`

**Назначение.** Увеличивает boot-info frame с 4 KB до 8 KB и `KernelMaxNumBootinfoUntypedCaps` с 240 до 500 для T580 (32 GB RAM, много фрагментированных untyped).

**Риск.** Меняет размер boot-info и количество untyped caps. Если патч ошибочен, root task может получить неполный список untyped или `Slot non-empty`.

**Альтернативы.**
- **Только для T580.** Уже сужено: патч не нужен на QEMU/других платформах. Это правильная стратегия: минимизировать область применения, а не убирать патч.
- **Проверить `Kconfig`.** `KernelMaxNumBootinfoUntypedCaps` уже вынесен в `Kconfig` (docs.sel4.systems/projects/sel4/configurations.html), дефолт 230/256. Если поднять это значение конфигурацией, патч сужается до размера frame. PR #721 предлагает вычислять значение, а не фиксировать.

#### 3.2. `load-image.patch`

**Назначение.** Копирует boot-модуль (root task) из `mods_end_paddr` в валидную RAM выше kernel region.

**Риск.** Меняет путь загрузки модулей. Если патч ошибочен, root task может быть загружен в зону, которая будет затёрта, или в невалидную RAM.

**Альтернативы.**
- **Долгосрочная:** root task как ELF-child (то же, что для DRHU). Тогда `load-image` не нужен: kernel грузит только себя, root task загружается через `Load_Elf` в userspace.
- **Среднесрочная:** проверить, можно ли обойтись без `load-image`, если GRUB грузит модули в другую зону (например, через `multiboot` с явным `paddr`).

## 4. Актуальные данные из первоисточников (ноябрь 2026)

### 4.1. Релизы и планы по обновлению

**`seL4` 16.0.0 (2026-07-22) — BREAKING.** Фокус: «validating assumptions, improving checks in unverified code, and fixing known issues» (`CHANGES.md`). Критичные исправления затронули **верифицированные конфигурации** (AArch32 cache maintenance, PAR_EL1 context switch). Для Schild TCB (x86_64 MCS) эти конкретные исправления не критичны, но принцип важен: upstream теперь аудирует код вне scope proof.

**`seL4` 17.0.0 (2026-10-30) — BREAKING.** Прямо релевантен нашим патчам: «fixing issues in unverified configurations … auditing code in verified configurations that is not covered by the scope of formal proofs» (`CHANGES.md`). Исправлены критические баги x86 (triple-fault при пользовательских флагах, VT-x на SMP) и AArch64 (trap/context switch системных регистров). Для x86_64 без VT-x часть исправлений может пересекаться с тем, что мы делаем патчами (например, поведение флагов на входе в ядро).

**Следующий релиз — BINARY COMPATIBLE** (`CHANGES.md`, «Upcoming release: BINARY COMPATIBLE»). Это снижает стоимость миграции после 17.0.0.

**Verification roadmap** (`sel4.systems/roadmap.html`):
- MCS functional correctness: завершение Q3/27.
- AArch64 confidentiality: Q2/26.
- Automated platform port verification: Q3/27 (снижает потребность в экспертах для новых платформ).
- Multikernel verification: Q3/28.

Для x86_64 MCS прямых сроков нет, но общий вектор — расширение verified scope, что косвенно уменьшает область, где мы вынуждены патчить.

### 4.2. Статус конкретных патчей в upstream

**`object-zeroing` — вероятно, можно убрать.** Upstream `03c71b6` переносит zeroing в `resetUntypedCap`; `41a13993` (#958) удаляет `memzero` из `createObject` для `SchedContextObject` и `ReplyObject`. Проверить, покрывает ли `resetUntypedCap` все типы Schild TCB.

**`MAX_NUM_DRHU` — пока не конфигурируем.** `KernelMaxNumBootinfoUntypedCaps` уже в `Kconfig` (дефолт 230/256). Для `MAX_NUM_DRHU` аналогичной опции нет, но PR #721 двигает boot-параметры в сторону конфигурируемости. Проверять каждый релиз.

**`bootinfo-8k` — можно свести к конфигурации.** `KernelMaxNumBootinfoUntypedCaps` настраивается. Если размер boot-info frame тоже станет настраиваемым (или 8 KB станет дефолтом для больших RAM), патч сузится или уйдёт. Проверить текущий `Kconfig` на размер frame.

**`smap` — upstream не развязал PRINTING и SMAP.** В `CHANGES.md` 16.0.0/17.0.0 нет коммитов, меняющих условие `!PRINTING && !DANGEROUS`. Патч остаётся, либо нужен собственный UART-драйвер в root task.

**`load-image` и `max-num-drhu` — архитектурная альтернатива.** Оба патча из-за GRUB-module. Если root task станет ELF-child (по образцу FS/MLS daemon), оба уходят архитектурно. Это уже зафиксировано в `HANDOFF.md` как Блок 3 (L).

### 4.3. Полезные `Kconfig`-опции (docs.sel4.systems/projects/sel4/configurations.html)

- `KernelMaxNumBootinfoUntypedCaps` — количество untyped caps в boot-info (дефолт 230/256).
- `KernelRootCNodeSizeBits` — размер root CNode (12–27). Если проблема `Slot non-empty` была связана с нехваткой слотов, возможно, решается увеличением этого значения.
- `KernelRetypeFanOutLimit` — лимит fan-out при retype.
- `KernelResetChunkBits` — размер чанка при preemptible zeroing в `resetUntypedCap`.

Эти опции можно проверить на предмет замены патчей конфигурацией.

### 4.4. Документация из первоисточников

- `docs.sel4.systems/projects/sel4/configurations.html` — полный список `Kconfig`-опций.
- `docs.sel4.systems/projects/sel4/releases/` — release notes, verified/unverified конфигурации, verification assumptions.
- `sel4.systems/Verification/assumptions.html` — что proofs **не** покрывают (boot code, cache maintenance, context switch, device address translation).
- `sel4.systems/roadmap.html` — verification roadmap с кварталами.
- `github.com/seL4/seL4/blob/master/CHANGES.md` — полный changelog.
- `github.com/seL4/seL4/pull/721` — `CONFIG_MAX_NUM_BOOTINFO_UNTYPED_CAPS`.
- `github.com/seL4/seL4/commit/03c71b6` — preemptible zeroing for retype.
- `github.com/seL4/seL4/commit/41a13993` — remove `memzero` from `createObject` for SC/Reply.

## 5. Стратегии минимизации без модификации ядра

### 5.1. Root task как ELF-child

Ключевая архитектурная стратегия. Сейчас root task — GRUB-module, и это порождает `max-num-drhu`, `load-image`, `bootinfo-8k`. Если root task загружается как ELF-child (по образцу FS/MLS daemon), GRUB грузит только kernel, а userspace-загрузчик (`Load_Elf`) размещает root task в своём VSpace. Тогда:

- `max-num-drhu` не нужен: `.boot.bss` может быть любого размера, GRUB не грузит модуль в зону memzero.
- `load-image` не нужен: kernel не копирует модуль из `mods_end_paddr`.
- `bootinfo-8k` может остаться только для untyped caps, но не для module placement.

Это L-работа (Блок 3), но она убирает три патча архитектурно, а не патчем.

### 5.2. Собственный UART-драйвер вместо `DebugPutChar`

Если root task пишет observability-лог через свой драйвер UART (как в bare-metal образе), зависимость от `CONFIG_PRINTING` снимается. Тогда `smap.patch` можно убрать: SMAP включается upstream-условием `!PRINTING && !DANGEROUS`, а PRINTING=0 больше не убивает observability. Это M-работа: нужен драйвер UART в root task и переключение `Put_String`/`Put_Hex` на него. Но она убирает патч из verified-ядра.

### 5.3. Runtime-проверки вместо патчей для object-zeroing

Вместо `object-zeroing.patch` можно добавить в root task runtime-проверку: после `Retype_Object` для TCB/Endpoint/Notification записать в объект паттерн, прочитать, сравнить. Если объект не был обнулён, root task узнает об этом до использования. Это не докажет zeroing, но даст fail-closed поведение без патча ядра.

### 5.4. Конфигурация вместо патча

Проверить, какие из патчей можно заменить на `Kconfig`-опции:

- `MAX_NUM_DRHU`: пока не конфигурируем, но upstream движется в эту сторону.
- `KernelMaxNumBootinfoUntypedCaps`: уже конфигурируем, PR #721 предлагает вычислять.
- `KernelRootCNodeSizeBits`, `KernelRetypeFanOutLimit`, `KernelResetChunkBits`: проверить, не решают ли проблему `Slot non-empty` без патча.
- `CONFIG_PRINTING` и SMAP: в 16.0.0/17.0.0 развязки нет, проверять каждый релиз.

## 6. Целевое состояние: чистое upstream-ядро

Идеал — `seL4` без патчей, с конфигурацией, которая покрывает все потребности Schild TCB. Для этого нужно:

1. **Root task как ELF-child** (убирает DRHU, load-image, часть bootinfo-8k).
2. **Собственный UART-драйвер** (убирает smap).
3. **Проверка upstream на zeroing** (убирает object-zeroing, если upstream покрывает все типы).
4. **Framebuffer вне security TCB** (уже сделано, патч остаётся, но не считается trust surface).
5. **T580-only патчи** (bootinfo-8k) — либо конфигурация, либо документированное исключение для одной платформы.

Если все пять пунктов закрыты, ядро остаётся upstream, а Schild TCB несёт только userspace-код (root task, daemons, SPARK-модули). Это соответствует принципу «механизм в ядре, политика и драйверы в userspace», который `seL4` и продвигает.

## 7. Рекомендуемый порядок действий

| Шаг | Стоимость | Что даёт | Verified-код | Риск |
|---|---|---|---|---|
| Проверить `resetUntypedCap` на избыточность `object-zeroing` | S | убирает 1 патч | **да, `createObject`** — единственный патч, покрытый refinement proof | низкий, аудит кода |
| Проверить `Kconfig` на `KernelMaxNumBootinfoUntypedCaps` / `KernelRootCNodeSizeBits` | S | сужает `bootinfo-8k`, возможно `Slot non-empty` | нет, конфигурация (не патч) | низкий |
| Обновление до 17.0.0+ | L | upstream-фиксы, возможно меньше патчей | условно: да, если 17.0.0 покрывает `object-zeroing`; иначе нет | BREAKING, нужна адаптация syscall-меток |
| Root task как ELF-child | L | убирает `DRHU` + `load-image` | нет, boot code (вне scope proof) | архитектурная правка, Блок 3 |
| Собственный UART-драйвер | M | убирает `smap` | нет, cache/context switch (вне scope proof) | средний, observability |
| Framebuffer вне TCB | — | уже сделано | нет, cosmetic (вне scope proof) | — |

**Ключевой вывод из колонки «Verified-код».** Из всех патчей только `object-zeroing` модифицирует код, покрытый formal proofs (`createObject`). Остальные лежат в зоне, которая по `sel4.systems/Verification/assumptions.html` и так вне scope proof (boot code, cache maintenance, context switch). Поэтому снятие `object-zeroing` — единственное действие, которое уменьшает поверхность verified-кода; остальные действия уменьшают число патчей, но не verified surface. Это меняет приоритет: `object-zeroing` первый не потому, что дешевле, а потому, что единственный, кто вообще трогает proof-покрытый код.

## 8. Ссылки

- `THREAT_MODEL.md` §9 — trust surface, AS8 (патчи).
- `START/PATCHES_CRYPTO_PLAN.md`, `START/HANDOFF.md`, `START/AUDIT_REGISTRY.md` — локальный handoff-каталог (gitignored; H102/H103, история патчей, эксперименты DRHU/SMAP).
- `docs.sel4.systems/projects/sel4/configurations.html` — `Kconfig`-опции.
- `docs.sel4.systems/projects/sel4/releases/` — release notes.
- `sel4.systems/Verification/assumptions.html` — verification assumptions.
- `sel4.systems/roadmap.html` — verification roadmap.
- `github.com/seL4/seL4/blob/master/CHANGES.md` — changelog.
- `github.com/seL4/seL4/pull/721` — `CONFIG_MAX_NUM_BOOTINFO_UNTYPED_CAPS`.
- `github.com/seL4/seL4/commit/03c71b6` — preemptible zeroing for retype.
- `github.com/seL4/seL4/commit/41a13993` — remove `memzero` from `createObject` for SC/Reply.
