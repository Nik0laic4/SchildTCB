# Schild TCB — Указатель документации и единый источник истины

> Служебный документ для навигации по `docs/`. Он отвечает на два вопроса:
> (1) какой документ каноничен для какой темы, (2) какие числа являются
> эталонными и где они проверяются механически. Никаких «агрегатных»
> заявлений — каждое утверждение указывает на модуль и команду проверки.

**Дата актуализации:** 2026-11-01 · **HEAD:** см. `git log -1`.

---

## 1. Каноничные документы (актуальные, поддерживаются)

| Документ | Тема | Роль |
|---|---|---|
| [`technical/ROADMAP.md`](technical/ROADMAP.md) | «Что дальше» | **Единый** источник истины о плане работ (W1–W10) и валидированном состоянии. |
| [`technical/ASSURANCE.md`](technical/ASSURANCE.md) | Assurance-кейс, TCB, фазы | Замороженная модель доверия (Tier A/B/C) + исторический лог фаз. «Что дальше» — в ROADMAP. |
| [`technical/THREAT_MODEL.md`](technical/THREAT_MODEL.md) | Модель угроз (активы, нарушители, T1–T9) | Живой документ; вход для контрактного усиления. |
| [`technical/SECURITY.md`](technical/SECURITY.md) | Модель безопасности по компонентам | Per-component заявления, MLS-правила, аппаратные контрмеры. |
| [`technical/BUILD.md`](technical/BUILD.md) | Сборка и запуск | Инструкции + воспроизводимость. |
| [`technical/CHANGELOG.md`](technical/CHANGELOG.md) | Только проверенные результаты | Журнал изменений (политика: verified results only). |
| [`technical/DEVELOPMENT_VECTORS.md`](technical/DEVELOPMENT_VECTORS.md) | Стратегия (референтные базы, DO-333) | Приоритеты «сейчас/позже/не делаем». |
| [`technical/TOOL_QUALIFICATION.md`](technical/TOOL_QUALIFICATION.md) | Версии инструментов + детерминизм | Шаг к DO-330/DO-333. |
| [`technical/ARCHITECTURE.md`](technical/ARCHITECTURE.md) | Технический data-sheet | Архитектура, ABI, история версий. |
| [`technical/SPARK_PROOF_TECHNIQUES.md`](technical/SPARK_PROOF_TECHNIQUES.md) | Приёмы доказательства (gnatprove gotchas) | Единый справочник приёмов; читать перед работой с proof. |

## 2. Требования с трассируемостью (пилоты)

| Документ | Пилот |
|---|---|
| [`technical/REQUIREMENTS_ARM64_NET.md`](technical/REQUIREMENTS_ARM64_NET.md) | ARM64 virtio-net |
| [`technical/REQUIREMENTS_BOOT_RELIABILITY.md`](technical/REQUIREMENTS_BOOT_RELIABILITY.md) | Boot counter / health check / watchdog |

## 3. Дизайн-заметки (референс)

| Документ | Тема |
|---|---|
| [`technical/BOOT_COUNTER_DESIGN.md`](technical/BOOT_COUNTER_DESIGN.md) | A/B boot counter + блокировка |
| [`technical/GENET_DRIVER_DESIGN.md`](technical/GENET_DRIVER_DESIGN.md) | Конспект драйвера GENET (Pi 4) |
| [`technical/VIRTIO_NET_L4RE_COMPARISON.md`](technical/VIRTIO_NET_L4RE_COMPARISON.md) | Сверка virtio-net с L4Re |
| [`technical/ARM64_VIRTIO_NET.md`](technical/ARM64_VIRTIO_NET.md) | Конспект порта AArch64 (файлы, seL4 gotchas, харнесс) |
| [`technical/HARDWARE.md`](technical/HARDWARE.md) | Карта железа ThinkPad T580 |
| [`technical/USE_CASE.md`](technical/USE_CASE.md) | Пилотный сценарий «Защищённый сетевой шлюз с MLS» |

## 4. Исторические / замороженные документы

Эти документы **не обновляются**; они фиксируют состояние на дату создания.
Для актуального состояния — см. каноничные документы из §1.

| Документ | Что фиксирует | Заморожен |
|---|---|---|
| [`technical/SEL4_INTEGRATION.md`](technical/SEL4_INTEGRATION.md) | Лог интеграции seL4 (Stage 5–8) | 2026-08-17 |
| [`technical/MCS_MIGRATION.md`](technical/MCS_MIGRATION.md) | Миграция на MCS API | 2026-10-03 |
| [`technical/RING3_NETWORK_MIGRATION.md`](technical/RING3_NETWORK_MIGRATION.md) | Миграция сети в Ring 3 | 2026-10-04 |
| [`SCHILD_TCB_AUDIT_REPORT.md`](SCHILD_TCB_AUDIT_REPORT.md) | Снимок self-аудита для сторонних инженеров | 2026-10-04 |
| [`technical/security/CVE-2026-SCHILD-01.md`](technical/security/CVE-2026-SCHILD-01.md) | Advisory (8 уязвимостей, исправлено) | 2026-08-05 |
| [`technical/security/CVE-2026-SCHILD-02.md`](technical/security/CVE-2026-SCHILD-02.md) | Advisory (5 уязвимостей, исправлено) | 2026-08-09 |

> Session-handoff'ы (`SESSION_*.md`) упразднены: «что сделано» — в `CHANGELOG.md`,
> «что дальше» — в `ROADMAP.md`, приёмы доказательства — в `SPARK_PROOF_TECHNIQUES.md`.

## 5. Единый источник истины — числа

Эти числа **не хардкодятся по памяти**, а читаются из механического вывода:

| Факт | Каноничное значение | Механическая проверка |
|---|---|---|
| Модули ядра в proof-наборе | **187** `.adb` (без `null/`) | `find src -name '*.adb' -not -path '*/null/*'` |
| Proof ядра (SPARK L4) | **`not-proved: 0`**; 130 proved / 56 skipped (прогон 2026-11-01, W11.3) | `bash scripts/prove_kernel.sh` → `obj/proof/report.txt` |
| Фокусно доказуемые (L4) | `schild_firewall` (7), `schild_signals`, `schild_frame_allocator`, `schild_server_security_policy`, `schild_mtf`, `schild_scheduler`, `schild_aes_cbc_engine`, `schild_crypto_fabric`, `schild_sentinel`, `schild_file_descriptors`, `schild_sha256_pad_guard`, `schild_sha_manager` | фокус-прогон одного модуля (команда ниже) |
| Демоны root-задачи (SPARK L4) | **8** (verify.gpr), `not-proved: 0`; `schild_boot_manager` 21, `schild_watchdog` 5, `schild_root_task` 76 checks | `bash scripts/verify.sh` |
| Сборка bare-metal (public) | 182 объект, 0 ошибок | `SCHILD_PROFILE=public ./build.sh` |
| Сборка seL4 (root task) | `root_task.elf` + `sel4_primary.iso` | `SEL4_PRIMARY=1 ./build.sh` |
| Сборка private-оверлея | ✅ доказано (`verify_private.sh`, `not-proved: 0`) | `SCHILD_PROFILE=private bash tools/sel4/build_rt.sh` + `bash scripts/verify_private.sh` |
| QEMU-маркеры | **20** (seL4) / **6** (standalone) | `bash scripts/run_tests.sh` |

> Число proved/skipped **недетерминировано** (флуктуирует из-за `gnatprove -j8`,
> напр. `schild_execution_fabric`, `schild_sentinel`). Стабилен только гейт
> `not-proved: 0`. W11 поднял базовый уровень: 6 модулей переведены `On` и
> доказаны (см. `CHANGELOG.md` W11). См. `ASSURANCE.md` §2.2.
>
> **Фокусно доказуемые модули** (доказуемы на Level 4, но канонический батч `-j8`
> может классифицировать их как SKIPPED): `schild_firewall` (7 подпрограмм),
> `schild_signals`, `schild_frame_allocator`, `schild_server_security_policy` и др.
> Проверка — фокус-прогон одного модуля (шаблон в `SPARK_PROOF_TECHNIQUES.md` §8).

## 6. Двухконтурная сборка и граница доказательства (важно)

Сборка двухконтурная: `SCHILD_PROFILE=public` (stub-модули) и
`SCHILD_PROFILE=private` (полные тела из `private/root_task/`).

| Профиль | Что компилируется | Что **формально доказано** |
|---|---|---|
| `public` (stub) | заглушки в `tools/sel4/src/` | ✅ `verify.sh` (8 демонов) + `src/03_crypto` |
| `private` (полный) | оверлей `private/root_task/{audit_logger,config_daemon,boot_manager}.adb` + `schild_net_runtime.c` | ✅ `verify_private.sh` доказывает 3 Ada-тела (`not-proved: 0`); `schild_net_runtime.c` — C (runtime-tested, как остальные C-шимсы) |

Закрыто (2026-11-01): полные (private) тела демонов доказаны на SPARK Level 4
через `scripts/verify_private.sh` (`not-proved: 0`). Единственные осознанные
пропуски — `Schild_Audit_Logger.Persist_Audit_Log` (`SPARK_Mode => Off`, SchildFS
I/O side-effect) и C-файл `schild_net_runtime.c` (C-шимс, не SPARK).

## 7. Как читать репозиторий (маршрут)

1. Пошаговый учебник (build → run → verify) — [`GUIDE.md`](GUIDE.md).
2. Начать с [`../README.md`](../README.md) и [`../PROJECT_PASSPORT.md`](../PROJECT_PASSPORT.md) — обзор.
3. Понять «что доказано» — [`technical/ASSURANCE.md`](technical/ASSURANCE.md) (модель доверия) + [`technical/THREAT_MODEL.md`](technical/THREAT_MODEL.md).
4. Понять «что дальше» — [`technical/ROADMAP.md`](technical/ROADMAP.md).
5. Воспроизвести — [`technical/BUILD.md`](technical/BUILD.md), команды из §5 выше.
6. Проверить историю проверенных результатов — [`technical/CHANGELOG.md`](technical/CHANGELOG.md).

