# Session handoff — W11: contract semantics (CBC, max-priority scheduler, MLS soundness) (2026-11-01)

> Для чистой новой сессии. Читать целиком, затем стартовать с «Осталось».

## 1. Тема сессии

Не «перевести body в On ради галочки», а **усилить контракты так, чтобы каждый
`Post` кодировал конкретное свойство безопасности** из `THREAT_MODEL.md` §7/§10
(assets A1–A6, свойства T1–T9). Правило сессии:

- `Pre` принимает **все** легитимные входы (anti-strangling, THREAT_MODEL §10.3).
- `Post` = **свойство безопасности** (confidentiality/integrity/availability).
- Liveness (легитимный трафик всё ещё течёт) — по KAT/рантайму, **не** по proof (§10.3).
- Вакуум запрещён; `pragma Assume` остаётся 0 (без escape-hatch).

## 2. Что сделано (проверено фокус-прогоном, `not-proved: 0`)

| Модуль | Контракт (свойство) | Модель угроз |
|---|---|---|
| `schild_aes_cbc_engine` (body Off→On) | `Ciphertext(I) = Plaintext(I) xor Context'Old.IV(I)` **и** `IV = Ciphertext` — полная CBC-цепочка (FIPS 800-38A): исключает ECB-replay и невыбеленную утечку | A1 |
| `schild_crypto_fabric.Process_Secure_Block` | пробрасывает CBC-свойство через шов (state + whitening + IV-advance) | A1 |
| `schild_mtf` (spec+body Off→On) | `Pre => S'Length > 0` (тотальность) + `Global => null` (детерминизм) — статическое ARINC-653 расписание не падает ни на каком tick | T5 |
| `schild_scheduler` | `Find_Next_Task(_In_Partition)` `Post`: возвращённая задача — **максимально-приоритетная** среди ready (нет обхода приоритетной задачи) | T5 |
| `schild_sentinel` | `Post => Is_Ok = (Is_Active and Integrity_Checked)` (вместо странгулирующего `Pre`) | A3 |
| `schild_file_descriptors.Check_Access` | `Post` = Bell-LaPadula **звучимость**: доступ выдаётся только при наличии открытого дескриптора совместимого уровня (no read-up / no write-down) | T3 |

Точная привязка tick→partition (MTF) и приоритетная диспетчеризация валидируются
рантайм-тестами `tools/sel4/tests/mtf_kat.adb` и `two_level_kat.adb` (liveness,
по §10.3).

**Полный свип (2026-11-01):** `not-proved: 0`, **129 proved / 56 skipped**
(старт сессии: 112/73). Все 6 усиленных модулей — `PROVED` в каноническом
батче. `verify.sh` (8 демонов) и `verify_private.sh` — `not-proved: 0`.
Сборка `build.sh` — 181 объект, 0 ошибок.

## 3. Gotchas сессии (дополняют SESSION_W10 §4)

1. **Приоритет операторов Ada**: `=` связывает сильнее, чем `xor`/`and`. В
   quantified `Post` выражение `C(I) = P(I) xor IV(I)` разбирается как
   `(C(I) = P(I)) xor IV(I)` → ошибка типов. Нужны скобки:
   `C(I) = (P(I) xor IV(I))`.
2. **`'Old` + индекс массива**: пиши `Context'Old.Initialization_Vector (I)`,
   а не `Context.Initialization_Vector'Old (I)` (парсер трактует `(I)` как
   аргумент атрибута).
3. **Равенство массивов из чужого пакета**: `A = B` требует `use`-видимости
   оператора из пакета типа → предпочитай поэлементное `(for all I => A(I) = B(I))`.
4. **Loop-инвариант «track max»** (планировщик): «Best_Id — witness с Max_Pri,
   и для всех J в First..Id: если ready, то Priority <= Max_Pri» — проверяется
   на входе (Id=First ⇒ пусто) и после каждой итерации. Образец —
   `schild_scheduler.Find_Next_Task`.
5. **Сужение Unsigned_64→Unsigned_32** (`Tick mod Period` в MTF) доказуемо,
   потому что результат mod < Period <= 2**32-1. Провайдер CVC5 берёт это сам.

## 4. Осталось (по приоритету)

1. **http_server** — блокируется НЕ только constrained array types (gotcha W10
   §4.5), но и `'Address` (`Schild_Debug_Render (Reply_Buf (Idx)'Address)`),
   `System.Address`, и вызовами `Off`-модуля `Schild_Schild_Fs` (gotcha §4.7).
   Нужен архитектурный вынос debug-render и файлового сервинга из доказываемого
   ядра + constrained buffer types.
2. **Off-by-design (trusted axiomatics, THREAT_MODEL §9)**: `schild_aes_ni_core`
   (S-box), `schild_hmac_sha256` (64-раундовый schedule), `schild_random_core` +
   `schild_rng_manager` (RDRAND asm), `schild_frame_allocator` (bitmap over global),
   `schild_kernel_logic` (бесконечный цикл + C-imports), `schild_schild_fs`
   (System + NVMe I/O). Валидируются KAT/рантаймом, не proof.
3. **Мёртвые заглушки** (не используются никем): `schild_sha256_pad_guard`,
   `schild_random_core`, `schild_rng_manager`, `schild_sha_manager`
   (`schild_audit_chainer` импортирует `Schild_Sha_Manager`, но тело хеширует XOR'ом,
   не вызывая `Compute_Sha_Digest`).
4. **`schild_file_descriptors.Check_Access`** — доказана только звучимость
   (одна импликация). Полная эквивалентность требует инварианта уникальности
   `Id` открытых дескрипторов (типовый инвариант или Pre).
5. **`schild_audit_chainer`** — `Post` всё ещё слабый (`Is_Chain_Valid` = константа
   True; `Block_Sequence_Id` = константа 1; XOR вместо крипто-хеша). Усилить на
   tamper-evidence `Current_Hash = Previous_Hash xor Payload` + убрать
   странгулирующий `Pre (Previous_Hash(I) /= 0)`.
6. Полный свип — **выполнен** (см. §2: `not-proved: 0`, 129/56).

## 5. Команды (без изменений)

```bash
cd /home/null/Рабочий стол/SchildTCB/src/schild_core
bash scripts/prove_kernel.sh      # полный свип 185 (~10 мин)
bash scripts/verify.sh            # 8 демонов root-задачи
bash scripts/verify_private.sh    # полные тела демонов
bash /tmp/focus.sh <module>       # фокус-прогон одного модуля
```

## 6. Каноничные доки

`docs/README.md` (указатель + числа), `ROADMAP.md` §1/§3, `CHANGELOG.md`
(verified results only), `THREAT_MODEL.md` §7 (T1–T9) + §10 (метод усиления).
