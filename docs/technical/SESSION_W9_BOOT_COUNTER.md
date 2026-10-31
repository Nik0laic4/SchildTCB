# Session handoff — W9.1/W9.2 boot counter + health check (2026-10-31)

> Документ для чистой новой сессии. Прочитать целиком, затем продолжать с
> раздела «Осталось».

## 1. Git-состояние

- Работа (код): **`596516f`** (W9.1 boot counter) + **`6966b2a`** (починка
  private-оверлея) + **`0716daa`** (W9.2 health check); документация — коммитом
  поверх (итоговый HEAD — см. `git log -1`). Ветки `arm64`/`master`/`origin`
  в синке, рабочее дерево чистое.
- Репозиторий: `/home/null/Рабочий стол/SchildTCB`.
- Proof-гейт `verify.sh`: **`not-proved: 0`**, `schild_boot_manager` 10 подпрограмм
  доказано, `schild_root_task` 65 checks доказано.

## 2. Что сделано за сессию (W9.1/W9.2)

- **Boot counter (A/B + порог блокировки)** — расширен `schild_boot_manager`
  (обе редакции: `tools/sel4/src/` stub + `private/root_task/` полная):
  - `Max_Boot_Attempts : constant Unsigned_64 := 3` — порог блокировки слота;
  - поля `Slot_A/B_Attempts`, `Slot_A/B_Locked`, `Both_Locked` («кирпич»);
  - `Failover` декрементирует попытки активного слота, блокирует при `0`,
    переключается **только на разблокированный** слот, иначе `Both_Locked`;
  - `Record_Successful_Boot` коммитит активный слот (восстанавливает бюджет);
  - предикаты `Slot_Locked` / `Is_Bricked`.
- **Контракты усилены до инварианта** (frame-корректные `Pre`/`Post`), все доказаны.
- **Self-test** в `schild_root_task.adb`: `[S7] T4` + новые `[S7] T5a/T5b`
  (порог блокировки → brick).
- **Энергонезависимое хранилище зафиксировано** в `docs/technical/BOOT_COUNTER_DESIGN.md`:
  NVMe LBA 2048 (GPT-gap) + HMAC-SHA256 тег; x86 CMOS 0x2E–0x31 как ранний fallback.
  NVMe/CMOS-обвязка отложена до «с железа».
- Документация: ROADMAP (W9.1 ✅, W9.2 ✅, next W9.3), DEVELOPMENT_VECTORS,
  THREAT_MODEL (A5/T7/§8), этот handoff.
- **Health check перед commit (W9.2)** — `Health_Status` (Network_Up, MLS_Valid),
  `Health_Ok`, `Commit_If_Healthy` (commit iff healthy, else failover);
  self-test `[S7] T6a/T6b`. Доказано `verify.sh` (10 подпрограмм).
- **Починка private-оверлея** (`6966b2a`): `build_rt.sh` BUILD_ROOT → корень репо;
  недостающий `Config_Authorize_Op` в private config-daemon; синхронизация
  private `schild_net_runtime.c` с публичным scaffold. `SCHILD_PROFILE=private`
  теперь собирается целиком.

## 3. Ключевые факты и gotchas

- **Frame conditions — обязательны.** Первый прогон упал на `not Both_Locked` в
  цепочке вызовов: постконтракт `Failover` не объявлял неизменность «другого»
  слота, и проверщик терял его значения после 2-го вызова. Фикс: постконтракт
  полностью описывает новое состояние (неизменённые поля + формула для
  `Active_Slot`). **Урок:** для мутаторов с `in out`-рекордом постконтракт должен
  быть frame-полным, иначе цепочки вызовов не доказываются.
- **`Max_Boot_Attempts = 3`** — порог блокировки; семантика «слот блокируется
  после 3-й неудачи» (счётчик = 0 ⟺ заблокирован).
- **Инвариант** (заявлен явно в `Pre`/`Post`): `Slot_X_Locked = (Slot_X_Attempts = 0)`,
  `Both_Locked = (Slot_A_Locked and Slot_B_Locked)`, активный слот всегда
  разблокирован при `not Both_Locked`.
- **`private/` не входит в proof-гейт.** `verify.gpr` доказывает только stub
  (`tools/sel4/src`). Полная версия (`private/root_task/`) компилируется
  (`SPARK_Mode Off`) и валидируется прямой компиляцией против stub-спеки + HMAC.
- **Починено:** `tools/sel4/build_rt.sh` ранее считал `BUILD_ROOT` на один уровень
  мелко (`src/` вместо корня репо), из-за чего `SCHILD_PROFILE=private` не находил
  оверлей. Исправлено на `../../../..`; заодно добавлены недостающий
  `Config_Authorize_Op` (private config-daemon) и синхронизация private
  `schild_net_runtime.c` с публичным scaffold.
- Инструменты НЕ в PATH: gnatprove 14.1.1 / GNAT 14.2.0 — как в
  `SESSION_CONTRACT_AUDIT.md` §3.

## 4. Команды

```bash
cd /home/null/Рабочий стол/SchildTCB/src/schild_core
bash scripts/verify.sh            # гейт: not-proved: 0 (boot_manager 10/10, root_task 65)
# полная версия (SPARK_Mode Off):
#   gcc -c --RTS=.../bare_runtime -I../../src -I../../src/03_crypto \
#       /home/null/Рабочий стол/SchildTCB/private/root_task/schild_boot_manager.adb
```

## 5. Осталось (по приоритету)

### A. Фаза надёжности — следующий шаг W9.3

1. **Watchdog** (W9.3) — хардварный таймер + «kick»-петля в root-задаче (⚠️ железо).
2. **Load/Save shim** (см. `BOOT_COUNTER_DESIGN.md` §5): сериализация
   `Boot_Manager ↔ NVMe-блок LBA 2048` + вызов `schild_nvme.Read/Write_Block`
   в root-задаче (нужно железо/QEMU-NVMe). Также реальные пробы health-check
   (e1000e link status, MLS validation) вместо явных `Health_Status`-агрегатов.
3. **Tryboot / Rescue slot** (W9.4) — конфиг bootloader (❌ Pi 4).

### B. Долги контрактов (перенесены из прошлой сессии)

1. `schild_boot_runtime` — `Refined_State`-абстракция (gotcha в SESSION_CONTRACT_AUDIT.md).
2. `Is_Derived_From` — мёртвый код; спека после подключения к cap_space.
3. `schild_firewall` — scaffold (Tier C).

### C. Релиз v0.1.0 — когда A закрыт
