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

- Минимальный Ada/C-заглушка (не полный root task): ретайп PML4/PDPT/PD/PT + ASID,
  вызов `Load_Elf(root_task_elf_start, size, PML4, ...)`, `TCB_Resume(entry)`.
- Практически повторяет `Launch_MLS_Server`/`Map_NetServer_VSpace` (механизм уже есть).
- Root task после этого — обычный ELF-child со своим PML4/CSpace, как даемоны (H87).

## 4. Патчи, которые снимаются

| Патч | Почему снимается |
|---|---|
| `max-num-drhu` | GRUB больше не кладёт root-task модуль в зону memzero — модуль уходит в userspace |
| `load-image` | kernel не копирует модуль из `mods_end_paddr` — грузит только себя |
| `bootinfo-8k` | module placement больше не нужен (остаётся только под untyped caps) |

## 5. План реализации (фазы)

1. **Фаза A** — собрать `root_task.elf` как отдельный ELF-child (blob, как даемоны) +
   `mini-bootstrap` (заглушка-загрузчик). Kernel стартует bootstrap вместо root task.
2. **Фаза B** — bootstrap ретайпит PML4 + `Load_Elf(root_task.elf)` + `TCB_Resume`.
   Проверить: run_tests 24/24 (все даемоны под root task работают).
3. **Фаза C** — убрать три патча ядра (`max-num-drhu`, `load-image`, `bootinfo-8k`),
   пересобрать kernel + root task, прогнать полный набор тестов.

## 6. Риски

- **Boot-цепочка** — если bootstrap падает, система не стартует (нет observability до UART-драйвера). Нужен ранний UART в bootstrap (или kernel `DebugPutChar` до переключения).
- **Slot-раскладка** — root task как ELF-child занимает слоты (Image_Frame_Base + mint), нужно выбрать окно без коллизий (см. `SLOT_MAP.md`).
- **Занятость CSpace** — bootstrap временно держит капы (PML4/CSpace), которые после `TCB_Resume` могут не освободиться — продумать передачу или переиспользование.

## 7. Оценка

Крупная, но **механически проработанная** работа: `Load_Elf`/`Load_Segment`/слот-механика
уже сделаны и проверены на четырёх даемонах (H87). Основная новизна — mini-bootstrap +
снятие трёх патчей (пересборка ядра). Ожидаемый выигрыш — diff к upstream seL4 сокращается
на 3 патча, «root task как GRUB-module» исчезает.
