# Session handoff — Контрактный аудит + подготовка к фазе надёжности (2026-10-31)

> Документ для чистой новой сессии. Прочитать целиком, затем продолжать с
> раздела «Осталось».

## 1. Git-состояние

- `arm64` = `master` = `origin` = **`0fcb0a0`**. Рабочее дерево чистое.
- Репозиторий: `/home/null/Рабочий стол/SchildTCB`.
- Полный proof: `not-proved: 0`, `~108 proved / ~77 out-of-proof` (см. §3).

## 2. Что сделано за сессию (2026-10-25 → 10-31)

- **Модель угроз** — `docs/technical/THREAT_MODEL.md` (assets A1–A6, adversary
  P1–P4 + ИИ-каскад как ось возможностей, trust boundaries TB1–TB4,
  assumptions AS1–AS5, карта T1–T9, seL4-аксиоматика).
- **Честные формулировки** — «0 unproved VCs» вместо «185 verified»; бейдж,
  README/PASSPORT/ASSURANCE/CONTRIBUTING приведены к единому виду.
- **Классификатор proof-отчёта** — awk → `scripts/classify_gnatprove.py`
  (детерминированный, один проход); `SKIPPED`+`NO-BODY` слиты в «out of proof».
- **CI e2e** — починены зависимости seL4 (`libxml2-utils`, `cpio`, `pyfdt`,
  `ply`, `typing_extensions`, PEP 668 → `--break-system-packages`).
- **Репо-полировка** — CI-бейджи, `CODE_OF_CONDUCT.md`, issue/PR-шаблоны,
  честный теглайн.
- **Усиление контрактов** (все доказаны, `not-proved: 0`):
  - `cap_space`: Cap_Copy, Cap_Mint, Cap_Delete, Cap_Retype
  - `process_manager`: Terminate_Process, Create_Process (+root-путь),
    Reap_Zombies, Init_Process_Table, Check_Mls_Compatibility,
    Find_Free_Slot, Find_Process, Wait_Process
  - `signals`: Send_Signal, Has_Pending_Signals, Deliver_Pending_Signal
  - `mls_assigner`, `ipc` (Write_Byte, Execute_Syscall),
    `net_spark_proofs` (убран вакуумный `then True`)

## 3. Ключевые факты и gotchas

- **Инструменты НЕ в PATH**: gnatprove 14.1.1 / GNAT 14.2.0 / gprbuild 22.0
  в `~/.local/share/alire/{releases,toolchains}/...`. Скрипты `verify.sh` /
  `prove_kernel.sh` находят их сами (globbing по `gnatprove_*`/`gnat_native_*`).
- **gnatprove `-j8` недетерминирован**: ~2 модуля (`schild_execution_fabric`,
  `schild_sentinel`) флипают PROVED/out-of-proof между прогонами. Стабильно
  только `not-proved: 0`. Число «proved» ~108 (наблюдалось 106–109) — **не
  хардкодить**; задокументировано в `ASSURANCE.md` (сноска к таблице §2.2).
- **Ada: private-глобалки не видны в контрактах публичных подпрограмм** — для
  `schild_boot_runtime` нужна абстракция `Refined_State`/`Refined_Global`/
  `Refined_Post` (прямой перенос глобалок в private-часть не компилируется,
  было откачено).
- **Enum loop invariant**: использовать `Signal_Type'Pos (T) < Signal_Type'Pos (S)`,
  а не `'Pred` (у `'First` нет предшественника).
- Фокус-прогон одного модуля: временный `.gpr` с `for Main use ("module.adb")`
  + `gnatprove -P … --level=4 --mode=all`, затем смотреть `gnatprove.out`.

## 4. Команды

```bash
cd /home/null/Рабочий стол/SchildTCB/src/schild_core
bash scripts/verify.sh            # 7 демонов root-задачи (Level 4)
bash scripts/prove_kernel.sh      # полный свип 185 модулей (~10 мин)
SCHILD_PROFILE=public ./build.sh  # bare-metal сборка
```

## 5. Осталось (по приоритету)

### A. Фаза надёжности (boot/update/recovery) — следующий крупный блок

1. **Boot counter** (логика A/B + порог блокировки слота B) — расширить
   `schild_boot_manager` (`private/root_task/` полный + `tools/sel4/src/`
   seL4-вариант). Определить энергонезависимое хранилище (NVMe / отдельная
   область) — пока не зафиксировано.
2. **Health check перед commit** — проверка сети + MLS перед фиксацией слота.
3. **Watchdog** — хардварный таймер (Pi BCM2711 / x86 PIT-APIC) + «kick»-петля
   в root-задаче. ⚠️ требует железа для валидации.
4. **Tryboot / Rescue slot** — конфиг bootloader (Pi). ❌ требует Pi 4.

### B. Остатки контрактов

1. `schild_boot_runtime` — `Refined_State`-абстракция (см. gotcha §3).
2. `Is_Derived_From` — мёртвый код (не вызывается); спека после подключения
   к операциям cap_space.
3. `schild_firewall` — scaffold (Tier C); контракты после наполнения.

### C. Релиз v0.1.0 — когда A закрыт и всё зелёное

- Тег `v0.1.0` (pre-release) + честные release notes + команды воспроизведения.
- Резать по `master` (x86_64); `arm64` пометить «experimental».
- Финальный клик «Create release» — в веб-интерфейсе (тег + notes готовлю я).
