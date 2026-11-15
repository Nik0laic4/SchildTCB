# Schild TCB — Traceability Matrix (Assurance Case, Block 4)

**Version:** v0.1 (draft) | **Date:** 2026-11-15
**Scope:** связь «требование → код → тест» для Assurance Case. Заполняется по мере
готовности блоков; записи для ещё не закрытых единиц помечены ⏳.

## 1. Как читать

- **Требование** — идентификатор из `THREAT_MODEL.md` (T*/AS*/R*/C*) или дорожной
  карты (H*/M*).
- **Код** — единица реализации (Ada/SPARK или C-шим).
- **Тест/доказательство** — чем подтверждено: `gnatprove`, host-KAT, `run_tests` маркер.

## 2. Матрица (закрытые единицы)

| Требование | Код | Тест/доказательство |
|---|---|---|
| H87 — code isolation (FS) | `Launch_FS_Daemon` + `schild_elf_loader` | run_tests `[FS] daemon: OK`, `[NVFS] VERIFY OK` |
| H87 — code isolation (MLS) | `Launch_MLS_Server` (v0.46) | run_tests `[S7.7] MLS Server: OK`, `[H88]` |
| H87 — code isolation (Config) | `Launch_Config_Daemon` (v0.50) | run_tests `[R3] Config validate@Top_Secret/Public`, `[CONTAINMENT] Config Daemon contained` |
| H87 — ELF-парсер | `Schild_Elf_Core` (SPARK On) | host-KAT `elf-kat` PASS + gnatprove |
| H87 — SchildFS parsing core | `Schild_Fs_Core` (SPARK On) | host-KAT `fs-core-kat` PASS (CRC32 + superblock/dir-entry) + gnatprove |
| AS6 — syscall seam ABI | `seam_abi_test` (host) | host-KAT `seam-abi` PASS (msgInfo round-trip/clamp/offset) |
| AS6 — spec | `SYSCALL_SEAM_ABI_SPEC.md` | (документ) |
| H88 — MLS IPC gate | `Schild_MLS_Policy.Authorize_IPC_Levels` | run_tests `[H88]` root/eq/up/dn + C-демоны |
| H99 — proof scope | scaffold-модули исключены | `prove_kernel` 180 modules (0 not-proved) |
| C1 — ring-0 C audit | `RING0_C_AUDIT.md` + `schild_uart_putc_raw` | build 184/0 + run_tests 24/24 (refactor, семантика не менялась) |
| H62/H63 — CRC32 + per-file CRC | `Schild_Fs_Core.CRC32` | host-KAT `fs-core-kat` (0xCBF43926) |
| H61 — HMAC-SHA256 superblock | `Schild_HMAC_SHA256` | host-KAT `hmac_kat` + `[NVFS] VERIFY OK` |

## 3. Открытые (⏳) — не включаются в Assurance Case до закрытия

| Требование | Причина |
|---|---|
| H87 — code isolation (NetServer) | `netserver.elf` собран, Load_Elf-обвязка pending — слот-проблема (mint-offset) |
| C1 — ring-3 UART/framebuffer драйвер | premature: bare-metal без ring-3; seL4 UART уже ring-3 |

## 4. Как заполняется дальше

При закрытии каждой единицы (NetServer → Load_Elf и т.д.) сюда добавляется строка
с точным указанием кода и теста. Полная версия (Block 4 final) дополнится
`gnatcov` покрытием и `TOOL_QUALIFICATION.md`.
