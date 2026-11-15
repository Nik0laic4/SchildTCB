# Schild TCB — Индекс документации (docs/technical)

**Навигация по технической документации.** Держите актуальным при добавлении новых документов.

## Ядро и архитектура

- `ARCHITECTURE.md` — общая архитектура, Tier A/B/C, границы TCB.
- `HARDWARE.md` — целевое железо (ThinkPad T580 и др.).
- `BUILD.md` — сборка (bare + seL4 профили), toolchain.
- `SEL4_INTEGRATION.md` — интеграция с seL4.
- `MCS_MIGRATION.md` — MCS-планировщик, бюджеты.

## Безопасность и доказательство

- `THREAT_MODEL.md` — модель угроз (T*/AS*/R*/C-§).
- `ASSURANCE.md` — assurance-аргументы, verified TCB.
- `SECURITY.md` — политики безопасности.
- `SPARK_PROOF_TECHNIQUES.md` — техники SPARK-доказательства.
- `SYSCALL_SEAM_ABI_SPEC.md` — ABI syscall-seam (AS6) + план фаззинга.

## H87 (code isolation) и драйверы

- `ELF_CHILD_LOADER_DESIGN.md` — ELF loader, слот-раскладка, mint-offset.
- `SLOT_MAP.md` — единая таблица CSpace-слотов (image/mint/shared/PML4 + системные окна).
- `ROOT_TASK_ELF_CHILD_DESIGN.md` — L-работа: root task как ELF-child (снятие 3 патчей).
- `RING3_NETWORK_MIGRATION.md` — миграция сети в Ring 3.
- `ARM64_VIRTIO_NET.md`, `GENET_DRIVER_DESIGN.md`, `VIRTIO_NET_L4RE_COMPARISON.md` — ARM64/virtio.

## Assurance Case (Блок 4)

- `TRACEABILITY.md` — матрица требование→код→тест.
- `TOOL_QUALIFICATION.md` — квалификация инструментов.
- `FINAL_AUDIT.md` — сводка assurance-доказательств.
- `RING0_C_AUDIT.md` — аудит ring-0 C (C1).
- `SEL4_PATCHES_ANALYSIS.md` — анализ 7 патчей seL4.
- `HEALTH_CHECK_DESIGN.md` — C9 heartbeat (liveness) дизайн.
- `C4_FUZZING_PLAN.md` — C4 seam fuzzing план (LLM harness, ASan/UBSan).

## Roadmap и история

- `ROADMAP.md` — дорожная карта (Блоки 2→3→4).
- `CHANGELOG.md` — история версий (v0.x → v0.51).
- `DEVELOPMENT_VECTORS.md` — векторы разработки.
- `RELEASE_NOTES_*.md` — релизные заметки.

## Прочее

- `BOOT_COUNTER_DESIGN.md` — boot-counter (A/B-слоты).
- `USE_CASE.md` — сценарий использования.
- `REQUIREMENTS_*.md` — требования (ARM64 net, boot reliability).

---

**Локальный handoff-каталог** `START/` (gitignored): `HANDOFF.md` (где мы),
`AGENT_RULES.md` (правила агента), `AUDIT_REGISTRY.md`, `AUDITOR_REVIEW.md` (внешний аудит),
планы даемонов (`FS_DAEMON_PLAN.md`, `H87_MLS_DAEMON_DESIGN.md`, `H88_MLS_IPC_DESIGN.md`,
`PATCHES_CRYPTO_PLAN.md`).
