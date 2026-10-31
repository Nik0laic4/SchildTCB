# Schild TCB — Boot Counter (A/B + lockout) — дизайн

**Version:** v1.0
**Date:** 2026-10-31
**Owner:** Ирганов А.Н.
**Status:** реализовано и доказано (W9.1 boot counter + W9.2 health-gated commit);
энергонезависимое хранилище **зафиксировано**, но NVMe/CMOS-обвязка отложена до «с железа» (см. §5).

---

## 1. Назначение

Boot counter решает одну конкретную проблему **доступности** фазы загрузки:
если слот A/B испорчен (постоянный сбой проверки SHA-256), система не должна
уходить в **бесконечный цикл перезагрузок**. После `Max_Boot_Attempts`
последовательных неудачных попыток слот **блокируется**, менеджер перестаёт
его выбирать и переключается на резервный; если заблокированы оба — система
**«кирпич»** и уходит в recovery/rescue.

Это **не** защита целостности от злоумышленника P4 (нет signed boot / HWRoT,
см. `THREAT_MODEL.md` §8) — это ограничение *ущерба доступности* от
постоянно неисправного слота.

---

## 2. Семантика (модель, доказанная в SPARK)

Логика живёт в `schild_boot_manager` (обе редакции: `tools/sel4/src/` stub +
`private/root_task/` полная). Контракты идентичны.

- `Max_Boot_Attempts : constant Unsigned_64 := 3` — порог блокировки слота.
- Состояние (`Boot_Manager`) расширено per-slot счётчиками и флагами:
  - `Slot_A_Attempts`, `Slot_B_Attempts` — оставшиеся попытки до блокировки;
  - `Slot_A_Locked`, `Slot_B_Locked` — слот исчерпал попытки;
  - `Both_Locked` — «кирпич» (оба слота заблокированы).
- **Инвариант** (заявлен явно в `Pre`/`Post` каждой мутирующей операции):
  1. `Slot_X_Locked = (Slot_X_Attempts = 0)`;
  2. `Both_Locked = (Slot_A_Locked and Slot_B_Locked)`;
  3. если `not Both_Locked`, то активный слот всегда **незаблокирован**
     (менеджер никогда не выбирает заблокированный слот).

### Операции

| Операция | Эффект |
|---|---|
| `Initialize` | слот A активен, `Boot_Count = 0`, оба слота с полным бюджетом (`= Max_Boot_Attempts`), ничего не заблокировано |
| `Failover` | декремент попыток активного слота; при `0` — блокировка; переключение на резерв **только если он разблокирован**; иначе `Both_Locked`; `Failed_Boot_Count := +1`, `Verified := False` |
| `Record_Successful_Boot` | `Boot_Count := +1`, `Verified := True`; коммит активного слота (восстановление бюджета `= Max_Boot_Attempts`, снятие блокировки) |
| `Slot_Locked` / `Is_Bricked` | чистые предикаты-помощники |

### Сценарий блокировки (детерминированный, при `Max_Boot_Attempts = 3`)

```
Init:        A=3 B=3 active=A
Failover x5: A=0(locked) B=1 active=B   # A заблокирован после 3 неудач
Failover x1: B=0(locked) Both_Locked    # оба заблокированы => brick
```

---

## 3. SPARK-контракты

`Failover` — ключевая операция. Её постконтракт полностью описывает новое
состояние (frame-корректность), чтобы вызывающий мог вести цепочку вызовов:

- `Failed_Boot_Count = Old + 1`, `not Verified`;
- `Boot_Count`, `Slot_A_Hash`, `Slot_B_Hash` не меняются;
- инвариант §2 (lock-флаги ⇔ счётчики; `Both_Locked` ⇔ оба заблокированы);
- активный слот декрементирован ровно на 1, резервный — не изменён;
- `Active_Slot` после вызова = резервный слот, если тот разблокирован, иначе
  остаётся прежним.

`Record_Successful_Boot` аналогично frame-корректен. Проверка — `verify.sh`
(`schild_boot_manager`: 8 подпрограмм доказано, `not-proved: 0`).

---

## 4. Энергонезависимое хранилище (решение)

Boot counter **должен переживать перезагрузку** — иначе он бесполезен. Поэтому
модель в RAM (`Boot_Manager`) должна сериализоваться в энергонезависимое
хранилище. Решение:

### 4.1 Каноническое хранилище — выделенный NVMe-блок

- **Расположение:** LBA **2048** в свободном GPT-gap. Диапазон LBA 2000+
  уже зарезервирован проектом под boot-log (`schild_nvme.Flush_Log_To_Nvme`);
  counter-блок размещается в отдельном фиксированном LBA и не пересекается
  с логом.
- **Размер:** один 512-байтовый блок (читается/пишется `schild_nvme.Read_Block /
  Write_Block`).
- **Целостность:** HMAC-SHA256 тег (тот же примитив `Schild_HMAC_SHA256`, что
  для верификации образов) по байтам 0..479. Обнаруживает порчу блока (но не
  подмену злоумышленником с доступом к образу — та же граница, что и signed
  boot, см. `THREAT_MODEL.md` §8).

### 4.2 Раскладка блока (512 байт)

| Смещение | Поле | Тип |
|---|---|---|
| 0..7 | magic `"SCHLDBC1"` | 8×U8 |
| 8..11 | version = 1 | U32 LE |
| 12..15 | reserved | 0 |
| 16..23 | `Boot_Count` | U64 LE |
| 24..31 | `Failed_Boot_Count` | U64 LE |
| 32 | `Active_Slot` (0=A, 1=B) | U8 |
| 33..36 | `Slot_A_Attempts` | U32 LE |
| 37..40 | `Slot_B_Attempts` | U32 LE |
| 41 | flags (bit0=A_locked, bit1=B_locked, bit2=Both_Locked) | U8 |
| 42..479 | reserved | 0 |
| 480..511 | HMAC-SHA256 tag (байты 0..479) | 32×U8 |

### 4.3 x86 early-boot fallback — CMOS

До того как root-задача подняла NVMe, ранняя запись «попытка загрузки начата,
но не зафиксирована» ведётся в **CMOS RTC 0x2E–0x31** (тот же диапазон, что
проверяет диагностический `tools/cmos_read.c`). Это **опциональный**
платформо-зависимый защёлкиватель попыток: при обрыве питания до коммита слот
всё равно декрементируется. Канонический источник — NVMe-блок; CMOS — fallback
на x86_64. На ARM64 (Pi 4) аналог — через bootloader `tryboot` (W9.4), не здесь.

---

## 5. Что отложено (граница «без железа»)

1. **Load/Save shim** — структурный round-trip `Boot_Manager ↔ Persistent_State`
   (`To_Persistent`/`From_Persistent`) ✅ доказан. Осталось: byte-упаковка в
   512-байтовый блок + HMAC-тег + вызов `schild_nvme.Read_Block/Write_Block`
   в root-задаче (нужно железо/QEMU-NVMe). В QEMU-демо root-задача работает
   от `Initialize` (свежее состояние).
2. **CMOS latch** — запись в RTC CMOS 0x2E–0x31 (нужен реальный x86 PIIX4/ICH).
3. **Связка с `schild_boot_runtime`** — `Boot_Status` (Booting/Stable/Faulted/
   Recovering) в bare-metal-ядре пока не связан с `schild_boot_manager` (это
   разные модули: первый — standalone-ядро, второй — seL4 root-задача).
   Сведение — отдельная задача конвергенции (см. ROADMAP §4).

---

## 6. Проверка (воспроизведение)

```bash
cd /home/null/Рабочий стол/SchildTCB/src/schild_core
bash scripts/verify.sh     # гейт: schild_boot_manager 8/8 + root_task 63 checks, not-proved: 0
# полная версия компилируется (SPARK_Mode Off, оверлей):
#   gcc -c --RTS=.../bare_runtime -I../../src -I../../src/03_crypto \
#       private/root_task/schild_boot_manager.adb
```

Self-test в `schild_root_task.adb`: `[S7] T4` (failover) + `[S7] T5a/T5b`
(порог блокировки → brick) — маркеры выводятся при `SEL4_PRIMARY=1` QEMU.

---

## 7. Health-gated commit (W9.2)

W9.2 добавляет «проверку здоровья перед коммитом»: слот фиксируется
(`Record_Successful_Boot`) только если система здорова — сеть поднята **и**
MLS-политика валидна. Иначе — `Failover` (слот не коммитится).

- `Health_Status` — запись `Network_Up : Boolean; MLS_Valid : Boolean`.
- `Health_Ok (Status) = Status.Network_Up and Status.MLS_Valid` (доказано).
- `Commit_If_Healthy (Manager, Status)`: при `Health_Ok` — `Record_Successful_Boot`,
  иначе — `Failover`. Постконтракт: при здоровье `Boot_Count = Old + 1 and Verified`,
  иначе `Failed_Boot_Count = Old + 1 and not Verified` (доказано).

Реальные пробы (что именно «сеть поднята», что «MLS валидна») отложены до железа:

- **сеть** — `Schild_E1000e.Read_Status` bit 1 (link up) / `Is_Ready`;
- **MLS** — валидация политики (`Schild_MLS_Policy` / `Validate_Config`).

В QEMU-демо `schild_root_task.adb` `[S7] T6a/T6b` передают статус явно
(агрегатом `Health_Status`), поэтому гейт доказуем без железа.

Proof: `verify.sh` — `schild_boot_manager` 10 подпрограмм, `schild_root_task`
65 checks, `not-proved: 0`.
