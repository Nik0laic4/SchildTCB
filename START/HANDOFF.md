# Schild TCB — Handoff (журнал между сессиями)

**Обновлён:** 2026-11-05 (сессия 12 — merge audit/v0.4 → master)
**Ветка:** master
**HEAD:** c04b44d (merge: audit v0.4 — H86 closed, FS daemon stage 2, H88 partial)
**Master:** 482cc9d → c04b44d (audit/v0.4-threat-model смержена --no-ff, Approved-by: human)

## Правила входа (читать первым, 5 минут)

1. `AGENT_RULES.md` v3.0 — бинарная граница Tier A, 10 запретов, 12 escalation-триггеров, gates, отчётность.
2. `HANDOFF.md` (этот файл) — где мы, что дальше, карта граблей.
3. `FS_DAEMON_PLAN.md` — если работа про FS daemon.
4. `AUDIT_REGISTRY.md` — детали по любой находке (grep по ID).

Не начинать код без: build PASS, verify PASS, run_tests PASS (5 gates из AGENT_RULES).

## Текущее состояние

**Профили:**
- public (default): scaffold, Persist = stub, run_tests 21/21 PASS
- private (opt-in): full daemon bodies, run_tests 21/21 PASS, Persist silent fail (H82)

**Архитектура daemons (все в root_task.elf, separate PML4 + CSpace):**
- MLS server (mls_server.c, C) — Bell-LaPadula, endpoint 4096
- NetServer (netserver.c + net_server.adb) — e1000e + TCP/IP (NVMe больше не его: H86)
- Config Daemon (config_daemon.c, C) — Junos-style commit
- FS Daemon (fs_daemon.c + fs_server.adb) — Stage 2: владелец NVMe + SchildFS, own PML4, slots +64..+75, NVMe BAR0 @0x620000

**Gates (последний прогон, 2026-11-04, до коммита H86):**
- bare-metal build: 182 objects, 0 errors
- seL4 build public: Done, без `[RT] ERROR`
- seL4 build private: Done, без `[RT] ERROR`
- verify.sh: all VCs proved
- run_tests public: 21/21 PASS (incl. [FS] daemon: OK, [NVME]/[NVFS] из FS daemon)
- run_tests private: 21/21 PASS
- check_build_lists.sh: PASS

**Закрыто в коде (26 находок):**
C14, C23, H22, H27, H32, H33, H34, H36, H42, H43, H52, H54, H55, H58, H67, H70, H75, H76, H77, H79, H80, H86, H68a (CI gate), Stage 1 FS daemon live.

Документы: AGENT_RULES v3.0 (154 строки, 11 секций, бинарная граница allowlist Tier A + 3-уровневый отчёт + 3 механизма автоматизации). Скрипты: escalation_check.sh, forbidden_check.sh, install_hooks.sh. Хуки: pre-commit + commit-msg (протестированы).

**Задокументировано в TM §12 + реестр (open, не закрыто):**
C1, C2, C3, C4, C8, C9, C10, H1-H5, H10, H65, H68, H82, H87.

## Карта граблей (что мы уже наступили)

### Build и сборка
- **H67:** build_rt.sh имеет ДВА списка (compile `for spec` + link `.o`). W11 добавил модуль в один, не в другой — SEL4_PRIMARY сломан с W11 по сей день. Fix: любой новый модуль в оба.
- **H68:** bare-metal (wildcard) и seL4 (explicit list) собираются по-разному. CI проверяет только bare-metal.
- **`Done: sel4_primary.iso` != PASS.** При ошибке Ada build.sh продолжает и собирает ISO из старого ELF. Ищи `[RT] ERROR` в выводе.
- **MLS_Rings mint range +44..+53 занят.** FS_EP на +44 конфликтовал, seL4 kernel: `Slot #4140 non-empty`. FS на +64..+74.
- **`[RT] ERROR` при `Done` (повтор H67-класса).** Убрали `Net_Nvme_Init` из body, но оставили в spec: `missing body for "Net_Nvme_Init"` в логе, при этом `182 objects, 0 errors` и `Done`. build.sh вернул 0. Всегда grep `[RT] ERROR`.

### Runtime / seL4
- **Yield не гарантирует CPU.** После TCBResume root task сделал Yield loop, daemon не стартовал (alive=0). Fix: Call(init) blocking, как у NetServer.
- **5 untyped недостаточно.** Setup_MCS_Thread нужны 2: SC и Reply. Итого 6.
- **UT filter QEMU 512M.** RAM кончается на 0x20000000. Filter `>= 0x20000000` не находит ничего. Диапазон 0x800000..0x20000000.
- **I : Natural не совпал с Cap_Ref.** `FS_Image_Frame_Base + I` требует `I : Word`.
- **MCS fault endpoint в caller CSpace.** TCBSetSpace резолвит fault_ep в root CSpace, не в daemon CSpace.
- **Device-untyped на QEMU i440fx — всё 16 МБ PCI-окно.** Retype до BAR0 NVMe занимает сотни фреймов; фиксированное окно слотов упирается в кадры NIC (`Slot #5120 in destination window non-empty`). Fix: `Next_Free_Slot`, который выставляет `Map_NetServer_VSpace`.
- **Новый VSpace = нет PT на 0x600000.** `Page_Map @0x620000` вернул `0x6003` (FailedLookup). FS daemon нужен свой `FS_PT_Mmio_Slot` + `Page_Table_Map (…, 0x600000)`.

### SPARK и Pre
- **Pre не enforced на Off callers.** SPARK доказывает для Pre, Off caller не проверяет. Runtime guard обязателен (C23, H33, H54).
- **Contract != runtime.** `not-proved: 0` не значит «работает». Persist_Audit_Log тихо падал (H82), Is_Ready=False.
- **Vacuity:** gnatprove ловит недостижимый Pre, не тавтологичный Post (M3, W11.1).

### FS и состояние
- **Stateful FS.** Next_Free_LBA, Strict_Read_Only, Current_Generation — глобалы. Boot 1 PASS != boot 2 PASS. Multi-boot regression.
- **Fresh device не форматировался.** H75: оба superblock невалидны -> Strict_Read_Only, FS никогда не создаётся.
- **Persist silent fail.** H82: root task Stage 7.2 до NetServer Stage 8.1D, NVMe Is_Ready=False, Init выходит молча.
- **test.txt дубликаты.** H77: Net_Nvme_Init создаёт при каждом boot, забивает FS, маскирует H74.

### Golden rule
- **Tier A -> Tier B body.** FS body (~430 Off) + NVMe body (~500 Off) линкуются в root_task.elf всегда. Public: stub не зовёт. Private: Persist зовёт напрямую -> нарушение golden rule в runtime (H65).
- **H87:** shared image RW. RO image невозможен без ELF loader (bss shared). OOB write из daemon = OOB в общий .bss.

### Терминал и процесс
- **Heredoc в zsh искажается.** Длинные pipe и `<<EOF` ломаются. Fix: `python3 -c ...`, файлы через `/tmp`, команды по одной.
- **Патчи вставляли снизу вверх** — перезапись файла. Fix: строго по одной команде, проверка `wc -l`/`grep` после.
- **`pragma Export` дублировался в ads + adb** -> Ada `representation item appears too late`. Fix: только в ads.

## Открытые находки (приоритет сверху)

**Critical (блокирует private production):**
- **H88** MLS не гейт IPC. Частично: `Role_FS_Server = Top_Secret` зарегистрирован (afdd4af), но enforcement отсутствует — `Mls_Authorize_Op` только в `mls_server.c`. Persist Top_Secret -> FS = read-up вне модели до Stage 3.
- **H72** Persist snapshot (перезапись audit.log с offset 0, не append): 4 КБ shared frame капает один Append. Открыто: incremental append (`Last_Persisted_Event_ID` в superblock).

**High:**
- **H68b** CI не делает полный SEL4_PRIMARY=1 build+run (H68a static gate закрыт; H68b = workflow_dispatch, ~30 мин, runtime regression).
- **H87** shared image RW (ELF loader v0.3.0).

**Medium (документировано в TM §12 + реестр v0.30):**
- C1 ring-0 C, C2 Pre не enforced, C3 spec Tier B, C4 syscall seam 1475 строк Off, C8 shared DMA cross-trust, C9 health через Tier B, C10 Verified TCB содержит Off.
- H1 P4/AS4, H2 IPC flood, H3 DoS, H4 TB3 не механический, H5 watchdog, H10 patches.
- **H89** claim «8 демонов» = 8 proof units (1 daemon); public stub; root_task 77 checks.
- **H90** budget FS: sporadic 5000/10000 вешает mount; round-robin 5000/5000; timeout на Persist Call не реализован.
- **N13** в `run_tests.sh` нет HTTP-запроса: путь http_server не исполняется в гейтах.

**Закрыто 04.11:** H86 (NVMe ownership), H91 (503, 0d0365e), H93 (containment + HM, 60b0ba5), H92 (shared frame, bd0d861), H65 + H82 (Persist via IPC, 6991f4b).

## Следующая сессия (первые 3 шага)

**Шаг 1: H72 append (`Last_Persisted_Event_ID` в superblock)**
- incremental append вместо snapshot: FS daemon хранит write-cursor в superblock, дописывает audit.log между boot
- полный 8 КБ-захват через chunked transfer (обойти 4 КБ shared frame)

**Шаг 2: enforcement H88 + HTTP через fs_ep (H91 (a))**
- level-check в IPC-контракте / диспетчере FS (read-up по-прежнему не контролируется)
- NetServer статику -> `fs_ep` (заменить 503 на реальную раздачу)

**Шаг 3: H89 (claim) + H90 (timeout на Persist Call)**
- поправить ASSURANCE/RELEASE_NOTES/README: «8 proof units», public vs private; verify_private.sh в CI
- timeout на Persist Call (неблокирующий send + poll)

## Журнал сессий

### 2026-11-03 (сессия 1)
- v0.4-v0.19: 15 коммитов аудита, 22 находки закрыты в коде
- Корневая работа: HTTP oversize guard (H33), e1000e Len clamp (H54), FS fresh-format (H75), Persist honest log (H70), build_rt fix (H67), Stage 1 FS daemon live
- Документы: AUDIT_REGISTRY (810 строк, v0.1-v0.19), AGENT_RULES v2.0, FS_DAEMON_PLAN (177 строк, §1-§11), TM §12 (C-§3.1 через C-§9, AS6-AS8, T10-T15, R9-R18)
- Уроки: 4 итерации фикса в Stage 1 (тип, filter, 5 untyped, Yield -> Call). Коллизия slot +44 с MLS. Heredoc в zsh не работает.

### 2026-11-03 (сессия 1, продолжение)
- v0.20: H68a CI gate (check_build_lists.sh, 37 строк) + AGENT_RULES v2.1 (4 грабли Stage 1)
- 848884b: check_build_lists.sh + ci.yml step (10s, на каждый push, ловит H67-класс)

### 2026-11-04 (сессия 2)
- v0.21: AGENT_RULES v3.0 (154 строки) + 3 скрипта автоматизации (escalation_check, forbidden_check, install_hooks) + git hooks pre-commit/commit-msg
- cef7cf3: 3 скрипта, 126 insertions. Тесты: Tier A без Approved-by блокируется, с Approved-by проходит. False positives на self-reference исправлены
- Документы: AUDIT_REGISTRY 865 строк, AGENT_RULES v3.0, HANDOFF

### 2026-11-04 (сессия 3, документарная; код не менялся)
- Сверка START/*: HANDOFF ссылался на AGENT_RULES v2.0 (реально v3.0); AUDIT_REGISTRY шапка v0.1 при 21 ревизии; H72 описан по состоянию до c804b99 (буфер уже 8 KB); FS_DAEMON_PLAN §2/§7/§10 отстали от кода (Launch уже есть, маркеров 21).
- Новый code-debt: комментарий в `schild_sel4_syscall.ads` всё ещё «Slots +44..+50, free from +44» при фактических +64..+74 (Tier A -> escalation при правке). README/ROADMAP не отражают FS daemon.
- 02.11 — ноль коммитов; 03.11 — 11 коммитов; 04.11 — 1 (процессные скрипты).

### 2026-11-04 (сессия 4) — H86 CLOSED (NVMe ownership -> FS daemon)
- v0.23 коммит: `Map_Nvme_Into_FS` (retype из NIC device-untyped + `Next_Free_Slot`), `FS_PT_Mmio_Slot`, маппинг BAR0 @0x620000 в PML4 FS daemon; NetServer лишился `Net_Nvme_Init` (56 строк) и `with Schild_Nvme`; `Fs_Init` делает Init_MMIO + SchildFS + self-test (маркеры `[NVFS]`); `fs_daemon.c` op=0 -> `schild_fs_init()`.
- Гейты: bare 182/0, seL4 public/private Done без `[RT] ERROR`, verify PASS, run_tests 21/21 public и private, check_build_lists PASS.
- Три итерации отладки (грабли в реестр v0.23): `[RT] ERROR: missing body for Net_Nvme_Init` при `Done` в логе; `Slot #5120 non-empty` (device-untyped QEMU покрывает всё 16 МБ PCI-окно, фиксированное окно слотов не годится); `Page_Map 0x6003` (в FS VSpace не было PT на 0x600000).
- Что не сделано: H65 остаётся open для private (Persist в root task), H82, H72 append, containment test FS daemon.

### 2026-11-04 (сессия 5) — PRE_H86_CHECK выполнен (после H86)
- Часть 1 (MLS): Исход A. `Mls_Authorize_Op` — только в `mls_server.c`; в `netserver.c`/`fs_daemon.c` авторизации нет; FS daemon отсутствует в `Server_Role`. -> H88 Critical.
- Часть 2 (8 демонов): `verify.gpr` = 8 proof units, из них 1 реальный daemon; public 291 check, root_task 77 checks; private `verify_private.sh` PASS (173 check), в CI не подключён. -> H89 Medium.
- Часть 3: H90 (budget 5000/5000 + общий timeout EP), H91 (HTTP->FS напрямую, после H86 #PF), H92 (shared DMA на 3 домена), H93 (HM model FS daemon).
- verify_private.sh прогнан вручную: PASS, 173 check, 12 units.
- Код не менялся; реестр v0.24.

### 2026-11-04 (сессия 6) — H91 CLOSED: 503 вместо fault
- 0d0365e: `Set_Local_FS` в `schild_http_server.ads/.adb`, `Local_FS := True` по умолчанию; `Handle_Request` при `not Local_FS` отдаёт `HTTP/1.0 503` (+35 байт) и не трогает SchildFS; `Net_Init` в NetServer ставит `False`.
- Гейты: bare 182/0; seL4 public/private `Done` без `[RT] ERROR`; verify PASS; run_tests 21/21 public и private; build lists PASS.
- Наблюдение N13: `run_tests.sh` не поднимает сеть, HTTP-путь в гейтах не исполняется — поэтому H91 и проскочил.

### 2026-11-04 (сессия 7) — H88 partial: FS daemon в политике MLS
- afdd4af: `Role_FS_Server` + `Default_Policy (Role_FS_Server) = Level_Top_Secret` в `schild_server_security_policy.ads`; в комментарии зафиксировано следствие BL (Internal пишет вверх -> запрещено, нужен отдельный путь для user files).
- Enforcement отсутствует: `Mls_Authorize_Op` всё ещё только в `mls_server.c`; `Call_IPC` уровня не несёт. Гейт — Stage 3.
- Гейты: те же, PASS.

### 2026-11-04 (сессия 8) — H93 CLOSED: containment + HM/launch модели
- 60b0ba5: `HM_Domain`/`Domain` + 4-й домен FS daemon в `schild_hm_model` и `schild_launch_model` (SPARK On); `Health_Monitor` ветка `HM_FS_Daemon`; `Launch_FS_Daemon` пишет `FS_TCB_Cap`/`FS_Entry`/`FS_Stack` и зовёт обе модели; root task: `Call_IPC(fs_ep,99)` -> `Wait(Fault_Slot)` (badge 0xE3) -> restart -> `[CONTAINMENT] FS daemon contained`; маркер в `run_tests.sh`.
- verify.sh: all proved (4 домена сходятся, контракты не ослаблены). run_tests 22/22 оба профиля.
- Грабли: `FS_EP_Slot` в root task без `use Schild_Sel4_Syscall` -> «non-visible declaration»; там только локальные rename — добавил локальный `FS_EP_Slot`.

### 2026-11-04 (сессия 9) — H90 исследован, H92 решение
- df0426d: выделенные `FS_Budget_Us`/`FS_Period_Us` (5000/5000) в `Launch_FS_Daemon`. Эмпирика: sporadic 5000/10000 **вешает mount** (поллинг NVMe прерывается на середине, `Call(init)` не возвращается; run_tests 22→9, стоп на `[NVFS] Mounting filesystem...`). Оставлен round-robin; реальное смягчение — timeout на Persist Call (Stage 3).
- H92 решение: shared frame @0x52A000 не замаплен в FS VSpace → отдельный FS-фрейм @0x540000 в Stage 3 (вместе с dispatch).
- Прочитана вся `docs/technical` (22 файла + 2 CVE) для полного контекста.

### 2026-11-04 (сессия 10) — Stage 3 ч.1: FS dispatch + shared frame + smoke
- bd0d861: `fs_daemon.c` — switch op 0..8 + 99 к Ada-экспортам; `schild_sel4_ipc.c` — `schild_sel4_call4` (4 MR) + `read_ipc_mr2/mr3`; `schild_sel4_syscall.ads/.adb` — `Call_IPC4` + `FS_Shared_Frame_Copy_Slot` (+76), mint+map shared frame в FS VSpace @0x52A000 (H92); root task — smoke `Call(fs_ep,7)` → `[FS] Is_Mounted: OK`; маркер в run_tests.
- Гейты: bare 182/0; seL4 public/private `Done` без `[RT] ERROR`; verify PASS; run_tests 23/23 оба; build lists PASS.
- Грабли: дубликат `Read_IPC_MR1` (уже был на строке 420) → «conflicts with declaration»; голый `Call_IPC`-statement нелегален в SPARK («return value cannot be ignored») → привязал к R и печатаю в failure-ветке.
- H92 решение уточнено: общий фрейм замаплен в FS VSpace (доступ сериализован однопоточным root task), отдельный фрейм не понадобился.

### 2026-11-04 (сессия 11) — Stage 3 ч.2: Persist через IPC (H65/H82 CLOSED)
- 6991f4b: `Persist_Audit_Log` + `FS_EP` (Unsigned_64), snapshot → `Shared_Copy_To` → `C_FS_Append` (`schild_fs_append_ipc`, Call4 op=5); `Fs_Append` реализован (open/create audit.log, snapshot Write_File, new_size); `AL` вынесен в процедуру, Persist перенесён из Stage 7.2 → после Launch_FS_Daemon.
- private: `[S7.2] Audit persisted to SchildFS (audit.log)`; public: `... unavailable` (честный stub). 2-boot на одном образе: boot2 `Mounted OK` + persisted — состояние переживает reboot.
- verify.sh + verify_private.sh PASS; run_tests 23/23 оба профиля.
- H72 остаётся open: snapshot (перезапись), не append; 4 КБ frame капает один Append.

### 2026-11-05 (сессия 12) — merge audit/v0.4 → master
- Ветка `audit/v0.4-threat-model` смержена в `master` --no-ff: `c04b44d` (`Approved-by: human`).
- Гейты прогнаны на audit-ветке (6991f4b) и на master (после слияния): 5/5 PASS + check_build_lists PASS (bare 182/0; seL4 public/private `Done` без `[RT] ERROR`; verify PASS; run_tests 23/23).
- Энв-грабля: в среде DeepSeek Harness системный `python3` падает (`Failed to import encodings`) из-за `PYTHONHOME`/`PYTHONPATH`, указывающих на mount приложения. `run_tests.sh` (`mkschildfs.py`) требует `env -u PYTHONHOME -u PYTHONPATH`.
- Открытые находки не изменились: H72 (append), H88 (enforcement), H89 (claim), H90 (timeout), H68b, H87.

### Следующая сессия (дата TBD)
- Начать с AGENT_RULES + HANDOFF (5 минут).
- Шаг 1: H72 append (`Last_Persisted_Event_ID`) + chunked 8 КБ-захват.
- Шаг 2: enforcement H88 + HTTP через `fs_ep` (H91 (a)).
- Шаг 3: H89 (claim) + H90 (timeout на Persist Call).

## Дополнить после каждой сессии

- Обновить шапку (дата, HEAD).
- Добавить в журнал (что сделано, что выучено).
- Обновить «Открытые находки» (что закрыто, что новое).
- Обновить «Следующая сессия» (первые 3 шага).
- Новые грабли — в «Карту граблей».

