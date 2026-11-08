# Schild TCB — Syscall Seam ABI (AS6) — формальная спека + план фаззинга

**Version:** v0.1 (draft) | **Date:** 2026-11-08
**Статус:** Блок 3, первый шаг AS6 (спека, не переписывание). Консолидирует
`ARCHITECTURE.md` §6, `MCS_MIGRATION.md` §3–5, `SEL4_INTEGRATION.md`.

---

## 1. Назначение

Формально зафиксировать ABI «сшива» (`Schild_Sel4_Syscall`) — единственного
места, где Ada/SPARK root task разговаривает с seL4-ядром. Сшив — **наибольший
доверенный компонент** (тело `SPARK_Mode => Off`, 1767 строк; аудит C4/C10,
THREAT_MODEL AS6/R10). Баг здесь = побег из CSpace/VSpace.

Порядок работ (по HANDOFF): **не переписывать**, а (1) зафиксировать ABI,
(2) фаззить маппинг ABI (C4), (3) только потом думать о memory-safe шимме.

## 2. Граница сшива (W4)

- **Спека `schild_sel4_syscall.ads`** — `SPARK_Mode => On`: типы (`Word`,
  `Cap_Ref`, `Message_Info`, `HM_Domain`) и операции SPARK-видимы, с контрактами
  (`Global => null`, `Pre` на валидность слотов/капов).
- **Тело `schild_sel4_syscall.adb`** — `SPARK_Mode => Off`: seL4-механизм
  (retype/map/MMIO/MSI/TCB*) — доверенная аксиоматика, не доказывается.
- Политика — в On-пакетах (`Schild_Launch_Model`, `Schild_HM_Model`).

## 3. Syscall ABI (x86_64, CONFIG_SYSCALL)

Источник: `MCS_MIGRATION.md` §3–4.

| Syscall | MCS № | Назначение |
|---|---|---|
| SysCall | -1 | инвокация + IPC Call |
| SysReplyRecv | -2 | reply + recv (MCS) |
| SysSend | -5 | fire-and-forget |
| SysRecv | -7 | recv с reply |
| SysNBRecv | -8 | recv non-blocking |
| SysWait | -9 | recv без reply (blocking) |
| SysNBWait | -10 | recv без reply (non-blocking) |
| SysYield | -11 | уступить таймслайс |
| SysDebugPutChar | -12 | отладка в UART |

Регистры: `RDI`=cap/badge, `RSI`=msgInfo, `R10/R8/R9/R15`=MR[0..3],
`R12`=reply (MCS), `RDX`=номер syscall. MR[4+] — в IPC-буфере.

## 4. Message-info encoding

`msgInfo = (label << 12) | (extraCaps << 9) | length`.

Инвокационные label'ы (x86_64 MCS, источник — `schild_sel4_ipc.c`):
`TCBWriteRegisters=3`, `TCBSetTimeoutEndpoint=9`, `TCBSetIPCBuffer=10`,
`TCBSetSpace=11`, `TCBResume=13`, `CNodeMint=22`, `IRQHandler_Ack=27`,
`IRQHandler_SetNotification=28`, `SchedControl_ConfigureFlags=33`,
`SchedContext_Bind=34`, `X86PDPTMap=39`, `X86PageDirectoryMap=41`,
`X86PageTableMap=43`, `X86PageMap=45`, `X86PageGetAddress=47`,
`X86ASIDPoolAssign=49`, `X86IRQIssueIRQHandlerIOAPIC=57`,
`X86IRQIssueIRQHandlerMSI=58`. `UntypedRetype=1` (по ARCHITECTURE §6.2).
IOMMU: три доп. label'а вставляются перед `X86PageMap` → сдвиг +3 поздних
(см. `LBL_X86*` в `schild_sel4_ipc.c`).

## 5. Cap-slot map (root CNode 2^19)

`Slot_Base = 4096` (выше boot-time untyped-региона). См. `.ads` §слоты:
MLS 4096–4101, NetServer 4102–4113, fault/IRQ 4114–4118, Config 4119–4124,
shared/ECAM 4125–4127, MLS-rings 4130–4149, image frames 4224+, MMIO 4608+.

## 6. Контрактованный интерфейс (выборка)

`Global => null` у всех операций; `Pre` на валидность:

- `Wait`/`NBWait`/`Call_IPC`/`Call_IPC4` — `Pre => Src > 0`.
- `Retype_Object` — `Untyped_Cap > 0 and Root_CNode > 0 and Num_Objects > 0`.
- `TCB_Set_Fault_Handler` — `TCB_Cap/CSpace_Root/VSpace_Root > 0`.
- `TCB_Write_Registers` — `TCB_Cap > 0 and RIP_Addr /= 0 and RSP_Addr /= 0`.
- `Page_Map`/`Page_Map_Rights`/`Page_Table_Map`/`Page_Get_Address` — `*_Cap > 0`.
- `SchedControl_ConfigureFlags`/`SchedContext_Bind`/`TCB_Set_Timeout_Endpoint` — `* > 0`.
- Launch-* (`Launch_MLS_Server`, `Launch_NetServer`, `Launch_Config_Daemon`,
  `Launch_FS_Daemon`) — `Global => null`.

## 7. Доверенная аксиоматика (не доказывается)

- Точное соответствие Ada-контрактов реальному seL4 ABI (syscall-номера,
  msgInfo-кодировка, MR/cap-слоты) — runtime-tested, не proved (AS6).
- C-шимсы: `schild_sel4_ipc.c`, `schild_sel4_syscalls.S`, `message_info.c`.

## 8. План фаззинга (C4)

Цель — поймать рассинхрон «Ada-контракт ↔ реальный ABI», не трогая тело.

1. **Единичный харнесс** (host-side, как `proto_test.c` для net-стека):
   скармливать `msgInfo`-значения (label/extraCaps/length) генератору и сверять
   с эталонной кодировкой (отдельная простая реализация).
2. **Свойства:** (a) `label`, `extraCaps`, `length` round-trip без потери бит
   для всего диапазона; (b) длина ≥ `MsgMaxLength` отвергается/клампится
   детерминированно; (c) MR[4+] попадают в IPC-буфер по смещению `1+N`.
3. **Кап-слоты:** пересечение диапазонов в slot-map недопустимо (статическая
   проверка в build; ловится `check_build_lists`-классом).
4. **Интеграция:** CI-джоба `seam-abi` (хост-юнит, ~секунды), до переноса
   какого-либо seL4-механизма.

## 9. Escalation / residual

- Любая правка тела `.adb` или C-шимсов — Tier A (allowlist), escalation.
- Loader H87 — отдельная единица (см. `ELF_CHILD_LOADER_DESIGN.md`).
