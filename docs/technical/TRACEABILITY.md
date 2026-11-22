# Schild TCB — Traceability Matrix (Assurance Case, Block 4)

**Version:** v0.2 (draft) | **Date:** 2026-11-22
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
| H87 — code isolation (NetServer) | `Map_NetServer_VSpace` + `Load_Elf` (v0.51) | run_tests `[S8.2] NetServer VSpace: OK`, `[E1000E] Init OK`, `[CONTAINMENT] core alive after fault` |
| H87 — ELF-парсер | `Schild_Elf_Core` (SPARK On) | host-KAT `elf-kat` PASS + gnatprove |
| H87 — SchildFS parsing core | `Schild_Fs_Core` (SPARK On) | host-KAT `fs-core-kat` PASS (CRC32 + superblock/dir-entry) + gnatprove |
| AS6 — syscall seam ABI | `seam_abi_test` (host) | host-KAT `seam-abi` PASS (msgInfo round-trip/clamp/offset) |
| AS6 — spec | `SYSCALL_SEAM_ABI_SPEC.md` | (документ) |
| H88 — MLS IPC gate | `Schild_MLS_Policy.Authorize_IPC_Levels` | run_tests `[H88]` root/eq/up/dn + C-демоны |
| H99 — proof scope | scaffold-модули исключены | `prove_kernel` 189 swept / 179 in-proof / 133 proved / 0 not-proved / 10 scaffold |
| C1 — ring-0 C audit | `RING0_C_AUDIT.md` + `schild_uart_putc_raw` | build 185/0 + run_tests 25/25 (refactor, семантика не менялась) |
| H62/H63 — CRC32 + per-file CRC | `Schild_Fs_Core.CRC32` | host-KAT `fs-core-kat` (0xCBF43926) |
| H61 — HMAC-SHA256 superblock | `Schild_HMAC_SHA256` | host-KAT `hmac_kat` + `[NVFS] VERIFY OK` |
| R23 — MLS per-file gate | `Schild_Schild_Fs.Authorize_File_Op` (7 FS-операций) | run_tests `[R23] Fs_Open write-down denied` + SPARK (per-file Level/Owner, delete owner-only) |
| W10 — AES-128 core no-OOB | `Schild_Aes_Ni_Core` (SPARK On) | gnatprove 0 unproved + KAT FIPS-197 2/2 |
| W10 — SHA-256 compress no-OOB | `Schild_Sha256_Compress` (SPARK On) | gnatprove 0 unproved + KAT RFC 4231/NIST 9/9 |
| Д3 — C9 liveness-detect | `Schild_Health_Monitor` (Update_Health + Record_Heartbeat/Set_Grace/Mark_Unhealthy) | gnatprove 0 unproved + run_tests 25/25 |
| C4 — shim fuzz (coverage-guided) | `shared_frame/seam/fs_dispatch/mls_dispatch_libfuzzer.c` | libFuzzer 60с: 0 crash (1.5M–24.8M runs, ASan/UBSan) |

### 2.1 Ключевые T/AS/R/C требования (THREAT_MODEL)

| Требование | Код | Тест/доказательство |
|---|---|---|
| AS6/R10 — syscall seam (Off, 1767 стр.) | `Schild_Sel4_Syscall` + C-шимы | `seam-abi` PASS + `SYSCALL_SEAM_ABI_SPEC.md` (спека) |
| R9 — ring-0 C, no containment | `RING0_C_AUDIT.md` + `schild_uart_putc_raw` | аудит + run_tests 24/24 |
| T15/R18 — FS metadata tamper (CRC32→HMAC) | `Schild_HMAC_SHA256` (H61) | `hmac_kat` + `[NVFS] VERIFY OK` |
| T14/M1 — PID reuse | monotonic per-slot PID (M1) | gnatprove + run_tests |
| C-§7 H93 — FS containment | 4-й домен в `schild_hm_model`/`schild_launch_model` | `[CONTAINMENT] FS daemon contained` + SPARK |
| C-§4 golden rule H65 — Persist via IPC | `Persist_Audit_Log` → `fs_ep` op=5 Append | run_tests `[FS] daemon: OK` |
| C-§7 H91 — HTTP→FS regression | `schild_http_server` `Local_FS=False` | run_tests 24/24 (503 вместо fault) |
| C-§9 — seL4 patches scope | `SEL4_PATCHES_ANALYSIS.md` | аудит (только `object-zeroing` в доказанном коде) |

## 3. Открытые (⏳) — не включаются в Assurance Case до закрытия

| Требование | Причина |
|---|---|
| C1 — ring-3 UART/framebuffer драйвер | premature: bare-metal без ring-3; seL4 UART уже ring-3 |

## 4. Как заполняется дальше

При закрытии каждой единицы (NetServer → Load_Elf и т.д.) сюда добавляется строка
с точным указанием кода и теста. Полная версия (Block 4 final) дополнится
`gnatcov` покрытием и `TOOL_QUALIFICATION.md`.
