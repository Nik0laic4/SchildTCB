# Schild TCB — C9 Health Probe Design (IPC liveness)

> Статус: дизайн на ревью (перед кодом). М-работа (3–5 дней).

## 1. Проблема

C9: health-gated commit (`Commit_If_Healthy` в `schild_boot_manager`) не должен
опираться на `Network_Up` от NetServer (Tier B) — это Tier B-утверждение.
Сейчас проба — заглушка (`Network_Up` хардкодится в self-tests
`schild_root_task.adb:176/184`); при посадке она обязана стать Tier A observable.

## 2. Дизайн (асинхронный ping через NBWait)

Idle loop root task уже делает `NBWait(IRQ_Ntfn_Slot) → Call_IPC → IRQ_Ack → Yield`
(`schild_root_task.adb:649-685`). Добавляем периодический health probe:

1. Каждому домену — no-op ping op (NetServer **уже имеет** `op=4` = bench noop,
   `netserver.c:82-83`; добавить no-op в MLS/Config/FS).
2. Каждые N итераций idle loop root task шлёт `Call_IPC(ep, ping_op)` домену.
3. Ответил в окне N итераций = healthy; нет ответа = unhealthy
   (`Network_Up`/`MLS_Valid = False` для `Commit_If_Healthy`).

## 3. Почему асинхронно, а не синхронный Call

Синхронный `Call_IPC` блокируется до reply; без MCS-timeout (H90 open, x86_64 MCS
слабее ARM) зависший домен навсегда заблокирует root task. Асинхронный ping
переиспользует существующий `NBWait + Yield` и не требует timeout-syscall.

## 4. Таймаут-политика

- Бюджет NetServer = 50000 us (50 мс) → окно ping ≥ 50–100 мс, чтобы не давать
  ложных «unhealthy».
- N итераций = `ping_window / idle_loop_period`; период idle loop калибруется,
  целевое окно ≈ 100 мс.
- Домен помечается unhealthy после **M ≥ 2** пропущенных окон подряд (гистерезис).

## 5. Notification

- `IRQ_Ntfn_Slot` (4116) — e1000e IRQ notification; **не переиспользовать** под health.
- Новый `Health_Ntfn_Slot` (badged) — таймер health независим от IRQ (нет инверсии
  приоритета).

## 6. Реализация (план)

1. `schild_sel4_syscall.ads`: добавить `Health_Ntfn_Slot` + `Ping_Op`.
2. `netserver.c`: op=4 уже есть; добавить no-op в `mls_server.c`/`config_daemon.c`/
   `fs_daemon.c`.
3. `schild_root_task.adb`: в idle loop каждые N итераций `Call_IPC(ep, ping)` каждому
   домену + трекать reply; результат подавать в `Commit_If_Healthy`.
4. Self-test `[S7] T6a/T6b` перевести на реальную пробу (убрать хардкод `Network_Up`).

## 7. Residual

Ping-liveness доказывает, что домен **отвечает**, а не что он честен (скомпрометированный
домен может ответить и соврать в данных). Это liveness-gate, не integrity-gate —
приемлемо для health-gated boot commit (целостность отдельно: HMAC-суперблок H61).
