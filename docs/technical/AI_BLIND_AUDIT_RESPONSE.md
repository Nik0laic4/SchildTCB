# Schild TCB — ответ автора на независимый статический аудит

> Ответ на [AI_BLIND_AUDIT_2026-11.md](AI_BLIND_AUDIT_2026-11.md) (аудит коммита `8d67ecc`).
> Дата: 2026-11-21.

Статусы: **fixed** — исправлено; **accepted** — принято (позитив/осознанный остаток); **deferred** — отложено отдельной задачей.

## Сводная таблица

| ID | Уровень | Статус | Как исправлено |
|---|---|---|---|
| F1 | Средняя | **fixed** | Удалены все 11 модулей (22 файла). 6 — устаревшие дубликаты (новые версии в свипе), 5 — уникальные (VMM/Блок 5, восстановим из git). |
| F2 | Средняя | **fixed** | Классификатор определяет OFF-STUB по **тексту тела** (детерминированно), вердикт gnatprove — только PROVED/NOT-PROVED; новый вердикт NO-OUTPUT для On-тел без вывода. `prove_kernel.sh` + `check_metrics_consistency.sh` дополнены полем `no_output`. |
| F3 | Низкая | **fixed** | `check_metrics_consistency.sh` добавлен в `spark-badge.yml` после `prove_kernel.sh`. |
| F4 | Низкая | **fixed** | Комментарий в `ci.yml` обновлён (полный свип теперь на каждый пуш через spark-badge). |
| F5 | Низкая | **fixed (F5a)** | Контракты усилены: `Mls_Authorize_Op` (Pre+Post), `Register_Process` (запись + запрет дублирования PID), `Check_Send`/`Check_Read` (двусторонние), `Get_Process_Context` (Post), `Deliver_Pending_Signals` (frame + Loop_Invariant). **F5b** (каскадный `Cap_Revoke` + транзитивный `Is_Derived_From`) — **deferred** (дизайн транзитивного замыкания). |
| F6 | Инфо | **fixed** | `verify.sh` матчит `(low\|medium\|high):` — все ненулевые серьёзности. |
| F7 | Инфо | **fixed** | `IN_UNIT_RE` расширен до `[A-Za-z0-9_.]+` (дочерние пакеты). |
| F8 | Инфо | **fixed** | В `arm64/README.md` добавлена явная пометка tier-статуса (не доказан, отдельный трек). |
| F9 | Позитив | **accepted** | Ноль `Post => True`/`pragma Assume`/обоснований/Warnings Off — сохраняется (охраняет `forbidden_check.sh`). |
| F10 | Позитив | **accepted** | Канонический metrics.json + арифметический гейт; поле `no_output` добавлено. Расширение метрик на строки шва C4 — отдельно. |
| F11 | Рекоменд. | **fixed** | Кейс №8 «мёртвый гейт» добавлен в `docs/methodology/cases.md`. |

## F1 — осиротевшие модули: что удалено и почему

Аудит прав по числу (11), но реально это две группы:

- **6 устаревших дубликатов** (в корне `src/`): `aes_ni_core`, `ecc_validator`, `ioapic_core`, `ipc_caps`, `msr_syscall_core`, `pcie_config_guard` — у каждого есть **новая версия в свипе** (`src/schild_core/src/…`). Старые копии — мёртвый код.
- **5 уникальных**: `debug_context_switcher`, `fpu_state_guard`, `vmx_context_guard`, `space` (наброски под будущий VMM, Блок 5) + `mount_manager` (заменён `schild_fs_server`).

Решение: удалить все 11 (VMM-модули восстановим из git при старте Блока 5).

## F5a — что именно усилено

| Модуль | Подпрограмма | Было | Стало |
|---|---|---|---|
| `schild_mls_policy.ads` | `Mls_Authorize_Op` | без контрактов | `Pre` (op∈0..2, уровни 0..4) + `Post` (op 0/1/2 → `Can_Read`/`Can_Write`/`Can_IPC`) |
| | `Register_Process` | `Post` = только счётчик+1 | `Post` = запись (PID/Level/Active) + `Pre` «PID не зарегистрирован» + frame (старые записи не меняются) |
| | `Check_Send`/`Check_Read` | односторонний `if Allowed then …` | двусторонний `Result = Allowed ⇔ …` |
| `schild_process_manager.ads` | `Get_Process_Context` | без контрактов | `Post` (найден → Pid, не найден → default) |
| | `Deliver_Pending_Signals` | без контрактов | frame `Post` (не-Running/Ready записи неизменны) + `Loop_Invariant` |

**Проверено:** `verify.sh` — all VCs proved (root task 106 checks, без изменения; `Mls_Authorize_Op` 25 checks, `Register_Process` 7 checks); `schild_process_manager` — фокусный gnatprove Level 4, 0 unproved.

## F5b — отдельная задача (deferred)

Каскадный `Cap_Revoke` + транзитивный `Is_Derived_From` требуют ограниченного транзитивного замыкания (bounded loop по 64 слотам, глубина ≤32) и доказательства loop-invariant — это не «дописать Post», а спроектировать модель. Заведено отдельной задачей.
