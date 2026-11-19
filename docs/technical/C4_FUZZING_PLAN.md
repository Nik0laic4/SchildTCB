# Schild TCB — C4 Seam Fuzzing Plan

> Статус: первая эмпирика получена; полный прогон — M-работа.

## Цель

C4 (syscall seam) — главный residual Tier A: 1475 строк SPARK_Off + C-шимы,
проверяются только ручным review. Фаззинг даёт эмпирическое свидетельство
«шим не падает на N входах», не заменяя формальную верификацию.

## Что сделано (первый шаг)

- `tools/sel4/fuzz/seam_fuzz.c` — host-харнес: MR-setup `schild_sel4_call4`
  (`b[1..4]`) + `set_mr`/`set_ec` (extra-cap окно `b[122..]`), граничные + 64-битные
  случайные входы, xorshift64 PRNG.
- Прогон: `gcc -fsanitize=address,undefined` → **10 000 000 итераций, 0 нарушений**
  (ASan/UBSan).
- `tools/sel4/fuzz/fs_dispatch_fuzz.c` — host-харнес диспатча `fs_daemon.c`
  (op-switch + `u32`-касты аргументов + reply-MR записи) со стабами seL4/Ada,
  2 000 000 итераций, 0 нарушений (ASan/UBSan). *Drift-оговорка:* это копия
  switch; следующий шаг — вынести реальный диспатч в общую функцию и
  `#include` её харнесом.

## Что НЕ покрывает текущий харнес

- Сам `syscall` (seL4-инструкция) — не host-fuzzable, в харнесе опущен.
- `schild_sel4_recv`/`replyrecv` (ассемблерные Recv/Reply stubs) — отдельный харнес.
- Даемонные dispatch (`fs_daemon.c`/`mls_server.c`) — читают `schild_recv_mr[0..3]`
  + shared frame; fuzz через Ada-клампы (M-работа).

## Дальше (по приоритету)

1. `schild_sel4_recv`/`replyrecv`/`call` (asm) — ассемблерный харнес или
   `#ifdef HOST_TEST`-обёртка, где `syscall` → возврат 0.
2. libFuzzer/AFL вместо xorshift (структурное покрытие + corpus).
3. Даемонные dispatch (C) — fuzz `schild_recv_mr[0..3]` + shared-frame копии.

## Честная формулировка для ASSURANCE

«C shim fuzzed with 10M iterations under ASan/UBSan, no crashes; formal
verification of the shim remains future work».
