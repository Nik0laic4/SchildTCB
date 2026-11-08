# Schild TCB — SPARK proof techniques and prover gotchas

> Каноничный справочник приёмов доказательства для этого репозитория. Собран из
> закрытых сессий (W8–W11) вместо разрозненных session-handoff'ов. Каждый пункт —
> проверенный факт, не гипотеза. Перед работой с gnatprove читать целиком.

## 1. Инструменты и среда

- gnatprove / GNAT / gprbuild **НЕ в PATH**, лежат в `~/.local/share/alire/...`:
  - gnatprove 14.1.1 — `~/.local/share/alire/releases/gnatprove_*/bin`
  - GNAT 14.2.1 — `~/.local/share/alire/toolchains/gnat_native_*/bin`
- Скрипты `scripts/verify.sh` / `prove_kernel.sh` находят их сами (globbing по
  `gnatprove_*` / `gnat_native_*`). Для ручного прогона — §8.

## 2. Гейты и недетерминизм `-j8`

- Каноничный гейт — **`not-proved: 0`** (и только он стабилен).
- Число proved/skipped **недетерминировано** из-за `gnatprove -j8`: пара модулей
  (`schild_execution_fabric`, `schild_sentinel`) флипает PROVED/out-of-proof между
  прогонами; в батче из 20 Main фокусно-доказуемый модуль (напр. `schild_firewall`)
  иногда классифицируется `SKIPPED`.
- **Вывод:** не хардкодить число proved; утверждать только `not-proved: 0` и
  per-module «фокусно доказуем».
- Классификатор `scripts/classify_gnatprove.py` читает `gnatprove.out` один раз,
  разбивает по маркерам `in unit <name>,` и печатает вердикт per-module:
  `NOT-PROVED` (есть `not proved`), `PROVED` (есть `proved (`), `SKIPPED`
  (иначе — body `Off` или нет тела).

## 3. Контракты: метод и frame conditions

- **Метод (`THREAT_MODEL.md` §10):** `Pre` принимает **все** легитимные входы
  (anti-strangling); `Post` = **свойство безопасности**; liveness — через
  runtime/KAT, не через proof; вакуум запрещён (`Post => True` недопустим);
  `pragma Assume` = 0 (никаких escape-hatch).
- **Frame conditions обязательны.** Для мутатора с `in out`-рекордом постконтракт
  должен быть frame-полным: перечислить неизменённые поля + формулу для изменённых.
  Иначе цепочки вызовов не доказываются (значения «теряются» после 2-го вызова).
  Примеры: `Failover` (boot_manager), `Tick`/`Kick` (watchdog),
  `Apply_Rate_Limit` (firewall).
- **Private-глобалки не видны в контрактах публичных подпрограмм** — нужна
  абстракция `Refined_State`/`Refined_Global`/`Refined_Post` (прямой перенос
  глобалок в private-часть не компилируется).

## 4. Буферы и byte-упаковка

- **Переменная длина буфера — паттерн:** nested `Put_U8/U16/U32` +
  `Pre (Buf'Length >= N + Payload'Length)` + `Post (Len = N + Payload'Length)` +
  `Relaxed_Initialization => Buf` + `Loop_Invariant (Idx - Idx'Loop_Entry = ...)`.
  Образцы: `schild_tcp_handler.Build_Tcp_Reply`, `schild_ipv4_handler.Build_Ipv4_Frame`.
- **Недостающий `Pre` на размер буфера** — частая причина «висящего» gnatprove
  (напр. `Build_Ipv4_Header` без `Hdr_Buf'Length >= 20`).
- **Byte-упаковка:** (1) смещение `Off : Natural` требует `Pre` на границы массива
  (`Off <= 504/508/511`); (2) сужение `Unsigned_32(Unsigned_64)` требует
  range-check → добавить `Pre`; (3) битовые литералы квалифицировать (`Unsigned_8'(1)`).
- **`http_server` prover-ограничение (РЕШЕНО W11.3):** неограниченный `Byte_Array`
  (`Byte_Index = Integer range 0..4095`) и циклы `for I in S'Range` по
  неограниченному `String` (индекс `Positive = 1..2^31`) взрывают gnat2why.
  **Решение:** constrained типы — `Request_Buffer (0 .. Max_Request_Len-1)` +
  `Pattern (1 .. 12)` (фиксированная ширина, паддинг пробелами) + явный
  `Length`-параметр. Образец — `schild_http_core` (`Str_Match`/`Extract_Path`/
  `Is_Debug_Path`, доказано, `not-proved: 0`).

## 5. Арифметика

- **Битовые свёртки → модульная арифметика** (`mod 2**16`, `mod 2**32`) — доказуемо,
  в отличие от `and`/`Shift_Right`/`not` (checksum RFC 1071).
- **Сужение `Unsigned_64`→`Unsigned_32`** (`Tick mod Period` в MTF) доказуемо,
  потому что результат `mod` < Period <= 2**32-1.
- **Приоритет операторов Ada:** `=` связывает сильнее, чем `xor`/`and`. В
  quantified `Post` ставить скобки: `C(I) = (P(I) xor IV(I))` — иначе разбирается
  как `(C(I) = P(I)) xor IV(I)` → ошибка типов.

## 6. SPARK-ограничения (чего нельзя)

- **`'Address` локальной строки недопустим в SPARK** → debug-маркеры убирать /
  выносить в Off-слой.
- **Функции с `in out` / мутацией глобала нелегальны в SPARK** → переводить в процедуры.
- **On-код не может вызывать Off-подпрограмму** (нужен contract или inline).
- **`'Old` + индекс массива:** писать `Context'Old.Component (I)`, а не
  `Context.Component'Old (I)` (парсер трактует `(I)` как аргумент атрибута).
- **Равенство массивов из чужого пакета:** `A = B` требует `use`-видимости
  оператора из пакета типа → предпочитать поэлементное `(for all I => A(I) = B(I))`.

## 7. Loop-инварианты

- **Буферный write-цикл:** `pragma Loop_Invariant (Idx - Idx'Loop_Entry = J);`
- **«Track max»** (поиск максимума по массиву): «Best_Id — witness с Max_Pri, и
  для всех J в First..Id: если ready, то Priority <= Max_Pri». Образец —
  `schild_scheduler.Find_Next_Task`.
- **Enum-цикл:** в инварианте использовать `T'Pos (A) < T'Pos (B)`, а не `'Pred`
  (у `'First` нет предшественника).

## 8. Фокус-прогон одного модуля

Готовый помощник (если `/tmp` сохранился): `/tmp/focus.sh <module>`. Иначе — шаблон:

```bash
cd /home/null/Рабочий стол/SchildTCB/src/schild_core
GP=$(ls -1d ~/.local/share/alire/releases/gnatprove_*/bin/gnatprove | head -1)
GNAT=$(ls -1d ~/.local/share/alire/toolchains/gnat_native_*/bin | head -1)
export PATH="$(dirname "$GP"):$GNAT:$PATH"
ROOT="$(pwd)"
cat > /tmp/focus.gpr <<GPR
project Focus is
   for Source_Dirs use ("$ROOT/src", "$ROOT/src/01_hardware",
                        "$ROOT/src/02_security", "$ROOT/src/03_crypto",
                        "$ROOT/src/04_userland");
   for Object_Dir use "/tmp/focus_obj";
   for Main use ("<module>.adb");
   package Compiler is
      for Default_Switches ("Ada") use ("-gnat2022", "-gnatwa");
   end Compiler;
end Focus;
GPR
rm -rf /tmp/focus_obj/gnatprove
gnatprove -P /tmp/focus.gpr --level=4 --mode=all --timeout=20
grep -c 'not proved' /tmp/focus_obj/gnatprove/gnatprove.out   # должно быть 0
```

## 9. Гейты (команды)

```bash
cd /home/null/Рабочий стол/SchildTCB/src/schild_core
bash scripts/prove_kernel.sh      # полный свип 187 (~10 мин)
bash scripts/verify.sh            # 8 демонов root-задачи
bash scripts/verify_private.sh    # полные тела демонов
SCHILD_PROFILE=public ./build.sh  # bare-metal сборка
```

