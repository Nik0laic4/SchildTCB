# Session handoff — W9.1 Boot counter (A/B + lockout) (2026-10-31)

> Документ для чистой новой сессии. Прочитать целиком, затем продолжать с
> раздела «Осталось».

## 1. Git-состояние

- Работа W9.1 (код) — коммит **`596516f`**; документация — коммитом поверх
  (итоговый HEAD — см. `git log -1`). Ветки `arm64`/`master`/`origin` в синке,
  рабочее дерево чистое.
- Репозиторий: `/home/null/Рабочий стол/SchildTCB`.
- Proof-гейт `verify.sh`: **`not-proved: 0`**, `schild_boot_manager` 8 подпрограмм
  доказано, `schild_root_task` 63 checks доказано.

## 2. Что сделано за сессию (W9.1)

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
- Документация: ROADMAP (W9.1 ✅, next W9.2), DEVELOPMENT_VECTORS,
  THREAT_MODEL (A5/T7/§8), этот handoff.

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
- **⚠️ Предсуществующий сдвиг пути в `tools/sel4/build_rt.sh`:** `BUILD_ROOT="$(cd ../../.. && pwd)"`
  из `tools/sel4` даёт `src/`, а `private/` лежит в корне репо — `SCHILD_PROFILE=private`
  при прямом запуске build_rt.sh не находит оверлей (`src/private/root_task`).
  НЕ чинил (вне скоупа W9.1); стоит проверить/поправить при следующем сборе
  приватного профиля.
- Инструменты НЕ в PATH: gnatprove 14.1.1 / GNAT 14.2.0 — как в
  `SESSION_CONTRACT_AUDIT.md` §3.

## 4. Команды

```bash
cd /home/null/Рабочий стол/SchildTCB/src/schild_core
bash scripts/verify.sh            # гейт: not-proved: 0 (boot_manager 8/8, root_task 63)
# полная версия (SPARK_Mode Off):
#   gcc -c --RTS=.../bare_runtime -I../../src -I../../src/03_crypto \
#       /home/null/Рабочий стол/SchildTCB/private/root_task/schild_boot_manager.adb
```

## 5. Осталось (по приоритету)

### A. Фаза надёжности — следующий шаг W9.2

1. **Health check перед commit** (W9.2): перед `Record_Successful_Boot`
   проверить сеть + MLS; только при успехе — коммит слота (иначе `Failover`).
2. **Load/Save shim** (см. `BOOT_COUNTER_DESIGN.md` §5): сериализация
   `Boot_Manager ↔ NVMe-блок LBA 2048` + вызов `schild_nvme.Read/Write_Block`
   в root-задаче (нужно железо/QEMU-NVMe).
3. **Watchdog** (W9.3) — хардварный таймер + «kick»-петля (⚠️ железо).
4. **Tryboot / Rescue slot** (W9.4) — конфиг bootloader (❌ Pi 4).

### B. Долги контрактов (перенесены из прошлой сессии)

1. `schild_boot_runtime` — `Refined_State`-абстракция (gotcha в SESSION_CONTRACT_AUDIT.md).
2. `Is_Derived_From` — мёртвый код; спека после подключения к cap_space.
3. `schild_firewall` — scaffold (Tier C).

### C. Релиз v0.1.0 — когда A закрыт
