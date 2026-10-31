# Schild TCB — Требования и трассируемость: фаза надёжности (boot counter + health check + watchdog)

**Version:** v1.0 | **Date:** 2026-10-31
**Scope:** `schild_boot_manager` + `schild_watchdog` (`tools/sel4/src/` + `private/root_task/`),
self-tests `[S7] T4–T7` в `schild_root_task.adb`.
**Цель:** формат «требование → дизайн → код → тест» для W9.1–W9.3, как шаг к DO-178C / DO-333
(см. `DEVELOPMENT_VECTORS.md`).
**Связанные:** `ROADMAP.md` (§3 W9), `BOOT_COUNTER_DESIGN.md`, `SESSION_W9_BOOT_COUNTER.md`,
`THREAT_MODEL.md` (A5/T7).

> Механическая проверка каждого требования — SPARK Level 4 (`verify.sh`, `not-proved: 0`)
> и/или маркер `[S7] T*` в UART-выводе QEMU (`SEL4_PRIMARY=1`). Никаких «агрегатных» утверждений.

---

## 1. Схема идентификаторов

| Префикс | Уровень |
|---|---|
| `BOOT-SYS-` | системное требование (направление целиком) |
| `BOOT-HLR-` | software high-level requirement (что делает софт) |
| `BOOT-LLR-` | software low-level requirement (производное, близко к коду) |

---

## 2. Системные требования (SYS)

| ID | Требование | Верификация |
|---|---|---|
| `BOOT-SYS-1` | A/B-загрузка не уходит в бесконечный цикл перезагрузок: слот блокируется после порога | `verify.sh` (`schild_boot_manager`); `[S7] T5a/T5b` |
| `BOOT-SYS-2` | Слот коммитится только при здоровье системы (сеть поднята ∧ MLS валиден) | `verify.sh` (`Commit_If_Healthy`); `[S7] T6a/T6b` |
| `BOOT-SYS-3` | Зависание root-задачи обнаруживается watchdog'ом (пропущенный kick) | `verify.sh` (`schild_watchdog`); `[S7] T7a/T7b` |
| `BOOT-SYS-4` | Счётчик загрузок переживает перезагрузку (логика round-trip) | `verify.sh` (`To_Persistent`/`From_Persistent`) |

---

## 3. High-level требования (HLR)

| ID | Требование |
|---|---|
| `BOOT-HLR-1` | A/B-состояние: активный слот, per-slot счётчики попыток, флаги блокировки, «кирпич» |
| `BOOT-HLR-2` | Failover: декремент активного слота, блокировка при `0`, переключение **только на разблокированный**, иначе «кирпич» |
| `BOOT-HLR-3` | Record_Successful_Boot: инкремент `Boot_Count` и коммит активного слота (восстановление бюджета) |
| `BOOT-HLR-4` | `Health_Ok = Network_Up ∧ MLS_Valid`; `Commit_If_Healthy` = commit iff healthy, иначе failover |
| `BOOT-HLR-5` | Watchdog: `Kick` сбрасывает countdown, `Tick` декрементирует, при `0` — fired |
| `BOOT-HLR-6` | Persistent round-trip: `To_Persistent`/`From_Persistent` сохраняют все поля счётчика |

---

## 4. Low-level требования (LLR)

| ID | Требование |
|---|---|
| `BOOT-LLR-1.1` | `Max_Boot_Attempts = 3`; инвариант `Slot_X_Locked = (Slot_X_Attempts = 0)`, `Both_Locked = (Slot_A_Locked ∧ Slot_B_Locked)` |
| `BOOT-LLR-2.1` | Failover frame-корректен: активный слот `−1`, резервный неизменён, `Active_Slot` = резервный iff разблокирован |
| `BOOT-LLR-3.1` | Коммит = `Slot_X_Attempts := Max_Boot_Attempts`, `Slot_X_Locked := False` |
| `BOOT-LLR-4.1` | `Commit_If_Healthy` делегирует `Record_Successful_Boot` / `Failover` |
| `BOOT-LLR-5.1` | Watchdog `Tick` post: `old=1 → Fired ∧ countdown=0`; иначе `countdown=old−1 ∧ ¬Fired`; `Period` неизменён |
| `BOOT-LLR-6.1` | `From_Persistent` сбрасывает hashes/`Verified` (не сохраняются) |

---

## 5. Матрица трассировки

| ID | Дизайн (файл) | Код (функция) | Тест (маркер/проверка) |
|---|---|---|---|
| `BOOT-SYS-1`/`HLR-1` | `BOOT_COUNTER_DESIGN.md` §2 | `Initialize`/`Failover`/`Slot_Locked`/`Is_Bricked` | `[S7] T4`, `T5a/T5b` |
| `BOOT-HLR-2` | `BOOT_COUNTER_DESIGN.md` §2 | `Failover` | `T5a/T5b` |
| `BOOT-HLR-3` | `BOOT_COUNTER_DESIGN.md` §2 | `Record_Successful_Boot` | `T4` |
| `BOOT-SYS-2`/`HLR-4` | `BOOT_COUNTER_DESIGN.md` §7 | `Health_Ok`/`Commit_If_Healthy` | `T6a/T6b` |
| `BOOT-SYS-3`/`HLR-5` | `SESSION_W9_BOOT_COUNTER.md` §3 | `schild_watchdog`: `Initialize`/`Kick`/`Tick`/`Expired` | `T7a/T7b` |
| `BOOT-SYS-4`/`HLR-6` | `BOOT_COUNTER_DESIGN.md` §5 | `To_Persistent`/`From_Persistent` | `verify.sh` (proof) |

---

## 6. Замечания

- Основной механизм проверки — SPARK Level 4 (`verify.sh` → `not-proved: 0`):
  `schild_boot_manager` 12 подпрограмм, `schild_watchdog` 5, `schild_root_task` 75 checks.
- Хардварная часть (таймер PIT/APIC/BCM2711, NVMe `Read/Write_Block`, bootloader) — отдельные
  требования с пометкой «deferred» (см. `BOOT_COUNTER_DESIGN.md` §5).
- Следующий шаг по `DEVELOPMENT_VECTORS.md`: расставить ID-комментарии в коде
  (`-- BOOT-HLR-2: ...`) и добавить покрытие кода в CI.