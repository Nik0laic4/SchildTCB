# Карта граблей (10 вещей, которые сломают сборку)

> Источник: `START/HANDOFF.md` §«Карта граблей» (санитизировано). Это «практикум»
> учебника: каждый пункт — реальная ошибка, уже совершённая в этом репозитории.
> Для последователя — что проверить, когда что-то не собирается/не грузится.

## Сборка

1. **Два списка, а не один (H67).** `build_rt.sh` имеет compile-список (`for spec`)
   и link-список (`.o`). Новый модуль добавляется в оба, иначе SEL4_PRIMARY
   сломан. Ловится `check_build_lists.sh`.
2. **`Done: sel4_primary.iso` ≠ PASS.** При ошибке Ada сборщик продолжает и
   собирает ISO из старого ELF. Всегда grep `[RT] ERROR` в выводе, не верь
   `Done`.
3. **`[RT] ERROR` при `Done`.** Класс H67: убрали тело из body, оставили в spec
   → `missing body` в логе, но `182 objects, 0 errors` и `Done`, exit 0.

## Runtime / seL4

4. **`Yield` не гарантирует CPU.** После `TCB_Resume` демон не стартовал
   (alive=0) из-за Yield-loop. Фикс: блокирующий `Call(init)`.
5. **UT filter QEMU 512M.** RAM кончается на `0x20000000`; filter
   `>= 0x20000000` не находит ничего. Диапазон `0x800000..0x20000000`.
6. **Новый VSpace = нет PT.** `Page_Map @0x620000` вернул `0x6003`
   (FailedLookup): у нового VSpace нет page-table на этот адрес. Нужен
   `Page_Table_Map` перед `Page_Map`.
7. **MCS fault endpoint в caller CSpace.** `TCBSetSpace` резолвит fault_ep в
   root CSpace, не в daemon CSpace.

## SPARK

8. **`Pre` не enforced у Off-callers.** SPARK доказывает для Pre-вызовов;
   Off-caller не проверяет → runtime guard обязателен на месте вызова.
9. **Тавтологичный `Post` не ловится.** gnatprove ловит недостижимый Pre, не
   тавтологичный Post — это ловит только ревью (см. [`cases.md`](cases.md) W11.1).
10. **Публичный spec и приватное тело — два места.** H89-оверлей: поле в
    публичном типе → синхронно обновить `private/root_task/*.adb`, иначе
    `verify_private.sh` падает `no selector`.

## Прочее

- **Stateful FS.** Next_Free_LBA, Strict_Read_Only — глобалы: boot 1 PASS ≠
  boot 2 PASS (multi-boot regression).
- **`PYTHONHOME`/`PYTHONPATH` ломают python3** (среда харнесса): системный
  `python3` падает `Failed to import encodings`. Фикс: `env -u PYTHONHOME -u
  PYTHONPATH bash scripts/...`.
- **Патчи вставляли снизу вверх** — перезапись файла. Фикс: по одной команде +
  проверка `wc -l`/`grep` после.

---

Это «глава 5» учебника: после `docker run` (быстрый старт) последователь
должен прочитать эти пункты — они превращают «почему у меня красное» в
«я знаю, где искать».
