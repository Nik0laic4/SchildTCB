# Session handoff — крипто + ядро (следующий блок W10) (2026-11-01)

> Для чистой новой сессии. Прочитать целиком, затем стартовать с «Осталось».

## 1. Git-состояние

- HEAD `343cd7e`; ветки `arm64` = `master` = `origin` (в синке), дерево чистое.
- Репозиторий: `/home/null/Рабочий стол/SchildTCB`.

## 2. Текущее валидированное состояние

- `prove_kernel.sh` (ядро, 185 модулей): **`not-proved: 0`**, ~112 proved / ~73 out-of-proof
  (диапазон ±2 из-за `-j8`; стабилен только `not-proved: 0`).
- `verify.sh` (root-задача, 8 демонов): `not-proved: 0`.
- `verify_private.sh` (полные тела демонов): `not-proved: 0` (кроме `Persist_Audit_Log`, Off/I/O).
- Сборка: `build.sh` — 181 объект, 0 ошибок; `SCHILD_PROFILE=private build_rt.sh` — компилируется.
- QEMU: `run_tests.sh` — 20 (seL4) / 6 (standalone) маркеров.

## 3. Что сделано (W10 — сеть, полностью)

- **arp** (Parse_Arp + Build_Arp_Reply), **icmp**, **ipv4** (Parse + Checksum + Header + Frame),
  **udp**, **tcp** (все подпрограммы) — переведены `On` и доказаны.
- `schild_net_types` (фундамент), `schild_net_parser/filter/limiter` — уже были `On`.
- Закрыт private-proof разрыв (`verify_private.sh` + `schild_boot_manager` `On` + `Pre` на `Verify_Image`).
- **http_server** — отложен (prover-ограничение, см. §4.5).

## 4. Ключевые приёмы / gotchas (выработаны за сессию)

1. **Переменная длина буфера** — решён паттерн: nested `Put_U8/U16/U32` +
   `Pre (Length >= N + Payload'Length)` + `Post (Len = N + Payload'Length)` +
   `Relaxed_Initialization` + `Loop_Invariant (Idx - Idx'Loop_Entry = ...)`.
   Образцы: `schild_tcp_handler.Build_Tcp_Reply`, `schild_ipv4_handler.Build_Ipv4_Frame`.
2. **Недостающий Pre на размер буфера** — частая причина «висящего» gnatprove
   (IPv4 `Build_Ipv4_Header` без `Hdr_Buf'Length >= 20`).
3. **Битовые свёртки → модульная арифметика** (`mod 2**16`, `mod 2**32`) — доказуемо,
   в отличие от `and`/`Shift_Right`/`not`.
4. **`'Address` локальной строки недопустим в SPARK** → debug-маркеры убирать/выносить.
5. **`http_server` prover-ограничение**: для неограниченного `Byte_Array`
   (индекс `Byte_Index = Integer range 0..4095`) проверщик не выводит границу
   подтипа (`B'First <= 4095` не доказуем) → нужны constrained array types.
6. **Функции с `in out`/мутацией глобала нелегальны в SPARK** → переводить в процедуры.
7. **On-код не может вызывать Off-подпрограмму** (нужен contract или inline).

## 5. Команды

```bash
cd /home/null/Рабочий стол/SchildTCB/src/schild_core
bash scripts/prove_kernel.sh      # полный свип 185 (~10 мин)
bash scripts/verify.sh            # 8 демонов root-задачи
bash scripts/verify_private.sh    # полные тела демонов
# фокус-прогон одного модуля: /tmp/focus.sh <module> (создан в прошлой сессии)
```

## 6. Осталось (по приоритету)

1. **Крипто**: `schild_aes_cbc_engine`, `schild_aes_ni_core`, `schild_sha256_pad_guard`,
   `schild_sha_manager`, `schild_hmac_sha256` (body `Off` — 64-раундовый message schedule
   вне L4-гейта по замыслу), `schild_random_core`, `schild_rng_manager`.
2. **Ядро/безопасность**: `schild_scheduler`, `schild_kernel_logic`, `schild_sentinel`,
   `schild_server_security_policy`, `schild_frame_allocator`, `schild_file_descriptors`,
   `schild_schild_fs`.
3. **http_server** — через constrained array types (или фиксированные буферы).
4. **Фокусно-доказуемые, но SKIPPED в `-j8` батче**: `schild_firewall`, `schild_signals`
   (проверить фокус-прогоном).

## 7. Каноничные доки

- `docs/README.md` — указатель + единый источник истины (числа, гейты, public/private).
- `ROADMAP.md` §1 (состояние) + §3 W10 (прогресс).
- `CHANGELOG.md` — только проверенные результаты.
