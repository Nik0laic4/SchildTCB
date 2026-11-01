# Session handoff — контрактное усиление (расширение Tier A/B) (2026-11-01)

> **АКТУАЛИЗАЦИЯ (2026-11-01):** сеть (arp/icmp/ipv4/udp/tcp) полностью доказана.
> Актуальный handoff — `SESSION_W10_CRYPTO_KERNEL.md`. Этот файл исторический.


> Документ для чистой новой сессии. Прочитать целиком, затем продолжать с
> раздела «Осталось».

## 1. Git-состояние

- `arm64` = `master` = `origin` (итоговый HEAD — см. `git log -1`). Рабочее дерево чистое.
- Репозиторий: `/home/null/Рабочий стол/SchildTCB`.
- Гигиена: сгенерированный `docs/SCHILD_TCB_AUDIT_REPORT.pdf` убран из git
  (источник — `SCHILD_TCB_AUDIT_REPORT.md` + `audit_report.css`), добавлен `*.pdf` в `.gitignore`.
- Proof-гейты:
  - `verify.sh` (root-задача): `not-proved: 0` — `schild_boot_manager` 21,
    `schild_watchdog` 5, `schild_root_task` 76 checks.
  - `prove_kernel.sh` (ядро, 185 модулей): `not-proved: 0`, `~108 proved / ~77 out-of-proof`
    (последний прогон — 107/78; см. `ASSURANCE.md` §2.2).

## 2. Что сделано за прошлые сессии (кратко)

- **Фаза надёжности W9:** boot counter (A/B + порог блокировки) ✅, health check
  перед commit ✅, watchdog логика ✅, Load/Save (round-trip + byte-упаковка
  `Encode_Block`/`Decode_Block`/`Verify_Block` + SHA-256 тег) ✅.
- **Долги контрактов:** `schild_boot_runtime` `Refined_State` ✅, `Is_Derived_From`
  (cap_space) ✅, `schild_firewall` (порт-блокировка + контракты) ✅.
- **High-assurance:** `REQUIREMENTS_BOOT_RELIABILITY.md`, `TOOL_QUALIFICATION.md`.
- **Починка private-оверлея** (`build_rt.sh` путь + `Config_Authorize_Op` + `net_runtime.c`).
- **Модель угроз** (`THREAT_MODEL.md`) + **контрактный аудит Tier-A** (W8) — `SESSION_CONTRACT_AUDIT.md`.

## 3. Ключевые факты и gotchas

- **Frame conditions — обязательны.** За сессию повторялось трижды: `Failover`
  (boot_manager), `Tick`/`Kick` (watchdog), `Apply_Rate_Limit` (firewall). Для
  мутатора с `in out`-рекордом постконтракт обязан объявлять неизменные поля,
  иначе цепочки вызовов не доказываются.
- **Byte-упаковка:** (1) параметр `Off : Natural` требует `Pre` на границы массива
  (`Off <= 504/508/511`); (2) `Unsigned_32(Unsigned_64)` требует range-check →
  `Pre` на `Encode_Block`; (3) битовые литералы квалифицировать (`Unsigned_8'(1)`).
- **`gnatprove -j8` недетерминирован** — `schild_execution_fabric`/`schild_sentinel`
  флипают PROVED/out-of-proof; в батче из 20 Main `schild_firewall` иногда
  классифицируется `SKIPPED`, хотя фокусно доказуем. Каноничный гейт — `not-proved: 0`.
- Инструменты НЕ в PATH: gnatprove 14.1.1 / GNAT 14.2.1 (см. §4). Фокус-прогон
  одного модуля — временный `.gpr` + `gnatprove -P … --level=4 --mode=all`.
- **`private/`-гейт закрыт (2026-11-01):** `scripts/verify_private.sh` доказывает
  полные тела (`private/root_task/`) — `not-proved: 0` (кроме `Persist_Audit_Log`, Off/I/O).

## 4. Команды

```bash
cd /home/null/Рабочий стол/SchildTCB/src/schild_core
bash scripts/verify.sh            # root-задача: boot_manager 21, watchdog 5, root_task 76
bash scripts/prove_kernel.sh      # полный свип 185 модулей (~10 мин)
SCHILD_PROFILE=private bash tools/sel4/build_rt.sh   # полная сборка (private-оверлей)

# фокус-прогон одного модуля (для контрактной работы):
#   GP=$(ls -1d ~/.local/share/alire/releases/gnatprove_*/bin/gnatprove | head -1)
#   GNAT=$(ls -1d ~/.local/share/alire/toolchains/gnat_native_*/bin | head -1)
#   cat > /tmp/f.gpr <<EOF
#   project F is
#      for Source_Dirs use ("$(pwd)/src", "$(pwd)/src/01_hardware",
#                           "$(pwd)/src/02_security", "$(pwd)/src/03_crypto",
#                           "$(pwd)/src/04_userland");
#      for Object_Dir use "/tmp/f_obj";
#      for Main use ("schild_arp_handler.adb");
#   end F;
#   EOF
#   PATH="$(dirname "$GP"):$GNAT:$PATH" gnatprove -P /tmp/f.gpr --level=4 --mode=all
```

## 5. Осталось — контрактное усиление (задача этой сессии)

Метод — `THREAT_MODEL.md` §10: для каждой security-критичной строки §7 вывести
точное свойство → SPARK-контракт → доказать (Level 4). Правила: **no vacuity**
(`Post => True` запрещён), **no escape hatches** (`pragma Assume` = 0), liveness —
через runtime-тесты, не через proof.

Кандидаты (сейчас out-of-proof, чистая логика, не железо), по приоритету:

1. **Сеть/протоколы (Tier B, прямой путь P1 → T1/T8):** `schild_arp_handler`,
   `schild_ipv4_handler`, `schild_icmp_handler`, `schild_http_server`,
   `schild_net_stack`, `schild_route_manager`, `schild_net_queue`.
2. **Крипто (Tier A-adjacent):** `schild_hmac_sha256` (spec уже `On`, body `Off`),
   `schild_aes_cbc_engine`, `schild_sha_manager`, `schild_sha256_pad_guard`,
   `schild_random_core`, `schild_rng_manager`.
3. **Ядро/безопасность:** `schild_scheduler`, `schild_kernel_logic`,
   `schild_kernel_state`, `schild_signals` (W8 частично), `schild_sentinel`,
   `schild_execution_fabric`, `schild_server_security_policy`, `schild_frame_allocator`,
   `schild_file_descriptors`, `schild_mmap_parser`, `schild_schild_fs`.

Порядок: сначала **сеть** (наибольшая атакующая поверхность), потом **крипто**, потом ядро.
После каждого модуля — фокус-прогон (см. §4) + коммит; в конце — `prove_kernel.sh` целиком.

## 6. Ссылки

- `THREAT_MODEL.md` — §7 (карта T1–T9), §10 (метод).
- `SESSION_CONTRACT_AUDIT.md` — W8 (что уже законтрактовано).
- `REQUIREMENTS_BOOT_RELIABILITY.md` — формат «требование → код → тест».
- `DEVELOPMENT_VECTORS.md` — §2 (high-assurance), §3 (сводный приоритет).
- `ROADMAP.md` — §3 W10 (эта задача).