# Schild TCB — Root task как ELF-child (дизайн, L-работа)

**Версия:** v0.1 (draft) | **Дата:** 2026-11-15
**Статус:** дизайн первой фазы L-работы (Блок 3 L). Консолидирует `SEL4_PATCHES_ANALYSIS.md` §5.1.

## 1. Зачем

Сейчас root task — **GRUB-module**. Из-за этого три патча ядра:
- `max-num-drhu` — ограничивает `.boot.bss` ядра, чтобы GRUB не клал модуль в зону `memzero`.
- `load-image` — копирует boot-модуль из `mods_end_paddr` в валидную RAM выше kernel region.
- `bootinfo-8k` — увеличивает boot-info под module placement.

Если root task загружается как **ELF-child** (по образцу FS/MLS/Config/NetServer через
`Load_Elf`), GRUB грузит **только kernel**, а userspace-загрузчик размещает root task в его
VSpace. Все три патча снимаются архитектурно.

## 2. Текущая цепочка vs целевая

**Сейчас:**
```
GRUB → kernel (seL4) → [DRHU] → [load-image: копирует root-task модуль] → root task (Ada)
```

**Цель:**
```
GRUB → kernel (seL4) → mini-bootstrap (маленький ELF-child) → Load_Elf(root_task.elf) → root task (Ada)
```

Ключевая сложность — «курица и яйцо»: root task сам грузит даемоны, а кто грузит root task?
Ответ — **mini-bootstrap**: минимальный userspace-загрузчик, который kernel стартует первым,
и который через существующий `Load_Elf` грузит `root_task.elf` в свой VSpace и переключается.

## 3. mini-bootstrap (что это)

- Минимальная **Ada**-заглушка (не полный root task): ретайп PML4/PDPT/PD/PT + ASID,
  вызов `Load_Elf(root_task_elf_start, size, PML4, ...)`, `TCB_Resume(entry)`.
- **Почему Ada, а не C:** `Load_Elf` живёт в `Schild_Elf_Loader`/`Schild_Sel4_Syscall` (Ada).
  C-шиммы (`schild_sel4_ipc.c`) дают только низкоуровневый `UntypedRetype`/`TCBSetSpace`;
  C-заглушке пришлось бы дублировать весь `Load_Elf` (ELF-парсер + retype + map + memcpy).
  Ada-заглушка переиспользует готовый `Load_Elf` без дублирования.
- Практически повторяет `Launch_MLS_Server`/`Map_NetServer_VSpace` (механизм уже есть).
- Root task после этого — обычный ELF-child со своим PML4/CSpace, как даемоны (H87).

**Boot-цепочка (проверено):** GRUB грузит kernel + root_task.elf как модуль; kernel
(`boot.c create_initial_thread`) стартует модуль на `ui_v_entry = 0x400000`. Для Phase B
модуль = `bootstrap.elf` (в нём blob `root_task.elf`), kernel-код НЕ меняется — только
сборка/GRUB: модуль = bootstrap, который `Load_Elf`'ит встроенный root task.

## 4. Патчи, которые снимаются

> **Уточнение (после B3, 24/24):** патчи НЕ снимаются напрямую — bootstrap сам
> является GRUB-модулем (~1.6 MB, содержит blob root task), поэтому
> `max-num-drhu`/`load-image` всё ещё нужны для загрузки bootstrap, а
> `bootinfo-8k` нужен под 500 untyped caps. Чтобы их снять, bootstrap надо
> встроить в kernel (не модуль) или сократить untyped caps. Фаза C переосмыслена.

| Патч | Почему *задумывалось* снять | Статус после B3 |
|---|---|---|
| `max-num-drhu` | root-task модуль уходит в userspace | ❌ всё ещё нужен (bootstrap — модуль) |
| `load-image` | kernel не копирует root-task модуль | ❌ всё ещё нужен (копирует bootstrap) |
| `bootinfo-8k` | module placement не нужен | ⚠️ нужен под 500 untyped caps |

## 5. План реализации (фазы)

1. **Фаза A** — собрать `root_task.elf` как отдельный ELF-child (blob, как даемоны) +
   `mini-bootstrap` (заглушка-загрузчик). Kernel стартует bootstrap вместо root task.
2. **Фаза B** — bootstrap ретайпит PML4 + `Load_Elf(root_task.elf)` + `TCB_Resume`.
   Проверить: run_tests 24/24 (все даемоны под root task работают).
3. **Фаза C** — *(пересмотрено)* снять три патча ядра: требует встроить bootstrap
   в kernel (не GRUB-модуль) и/или сократить `MaxNumBootinfoUntypedCaps` < 500.
   Отдельная крупная работа.

## 6. Риски

- **Boot-цепочка** — если bootstrap падает, система не стартует (нет observability до UART-драйвера). Нужен ранний UART в bootstrap (или kernel `DebugPutChar` до переключения).
- **Slot-раскладка** — root task как ELF-child занимает слоты (PML4/PDPT/PD/PT + image + mint ~274), а свободное окно после демонов узкое (Image_Frame_Base 4224..4430 = 207). Нужно либо переиспользовать демон-окна (bootstrap работает ДО root task, потом они освобождаются), либо пересмотреть mint-offset. Координация слотов bootstrap↔root task обязательна (см. `SLOT_MAP.md`).
- **Занятость CSpace** — bootstrap временно держит капы (PML4/VSpace), которые после `TCB_Resume` могут не освободиться — продумать передачу или переиспользование.
- **VSpace root task** — root task сейчас бежит в init VSpace (`VSpace_Slot=3`); как ELF-child он бежит в НОВОМ PML4, поэтому `Schild_Root_Task` должен использовать новый VSpace (не слот 3) для маппинга shared-фреймов даемонов.
- **Размер root task (~1087 кадров)** — `root_task.elf` имеет 2 PT_LOAD сегмента, суммарный MemSiz ≈ 4.25 MB (≈1087 кадров, в основном Ada-`.bss`). **Решено (A-путь):** CNode увеличен до 14 (`KernelRootCNodeSizeBits=14`, 16384 слотов) — свободное непрерывное окно ~8732 слота > 1087. Verified: run_tests 24/24 (MCS=ON).

## 7. Оценка

Крупная, но **механически проработанная** работа: `Load_Elf`/`Load_Segment`/слот-механика
уже сделаны и проверены на четырёх даемонах (H87). Основная новизна — mini-bootstrap +
снятие трёх патчей (пересборка ядра). Ожидаемый выигрыш — diff к upstream seL4 сокращается
на 3 патча, «root task как GRUB-module» исчезает.
