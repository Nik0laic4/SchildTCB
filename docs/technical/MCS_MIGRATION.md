# seL4 MCS — миграция root-задачи (план и контекст)

> Статус: **завершено** — root-задача переведена на MCS API, валидирована в QEMU
> (`run_tests.sh`: все 12 маркеров PASS, 0 ошибок).
> Дата: 2026-10-03.

## 1. Цель

Перевести root-задачу seL4-ветки (`SEL4_PRIMARY=1`) с **non-MCS** API на
**MCS** (Mixed Criticality Systems), чтобы получить жёсткую временную
изоляцию — ядерные CPU-бюджеты (scheduling contexts), а не только
кооперативный MTF.

## 2. Что уже сделано

- **MCS-ядро собрано** и установлено в `tools/sel4/kernel.elf`:
  `KERNEL_MCS=ON scripts/build_sel4_kernel.sh`
  (x86_64 pc99, `CONFIG_KERNEL_MCS=1`; сборка без ошибок — риск снят).
- В `schild_sel4_syscalls.S` обновлены номера syscall'ов (см. §3): `SysSend -5`,
  `SysRecv -7`, `SysYield -11`, `SysDebugPutChar -12`, `SysNBRecv -8` (без изменений).
- `build_sel4_kernel.sh` поддерживает `KERNEL_MCS=ON`.

## 3. Syscall labels (MCS enum, x86_64)

Источник: `seL4/build-mcs/gen_headers/arch/api/syscall.h`.

| Syscall | MCS | non-MCS |
|---|---|---|
| SysCall | -1 | -1 |
| **SysReplyRecv** | -2 | (был SysReply -6) |
| SysNBSendRecv | -3 | — |
| SysNBSendWait | -4 | — |
| SysSend | -5 | -3 |
| SysNBSend | -6 | — |
| SysRecv | -7 | -5 |
| SysNBRecv | -8 | -8 |
| SysWait | -9 | — |
| SysNBWait | -10 | — |
| SysYield | -11 | -7 |
| SysDebugPutChar | -12 | -9 |

## 4. ABI регистры x86_64

Источник: `seL4/include/arch/x86/arch/64/mode/machine/registerset.h`.

| Регистр | Назначение |
|---|---|
| RDI (0) | `capRegister`, `badgeRegister` |
| RSI (1) | `msgInfoRegister` |
| R12 (5) | `replyRegister` (только MCS) |
| R13 (6) | `nbsendRecvDest` (только MCS) |
| RDX (8) | номер syscall'а (`movq $-N, %rdx`) |

## 5. Ключевые сигнатуры MCS

### seL4_ReplyRecv (заменяет SysReply)
```c
seL4_ReplyRecv(src, msgInfo, sender, reply);
// src    = cap endpoint для recv   -> RDI
// reply  = cap reply object        -> R12
// msgInfo= info                    -> RSI
// sender = out: badge
```
В MCS **нет отдельного SysReply** — reply всегда = reply + recv.

### seL4_TCB_Configure (MCS, manual_label `tcb_configure_mcs`)
```c
seL4_TCB_Configure(tcb, cspace_root, cspace_root_data,
                   vspace_root, vspace_root_data, buffer, bufferFrame);
// 7 параметров, БЕЗ fault_ep (в non-MCS fault_ep был 2-м параметром).
```
В MCS fault handler **не задаётся** через TCBConfigure — fault идёт через
**Reply-объект**.

### seL4_SchedControl_ConfigureFlags
```c
seL4_SchedControl_ConfigureFlags(schedcontrol, schedcontext,
                                 budget, period, extra_refills, badge, flags);
// budget = timeslice (мкс); period = период (мкс).
```

### seL4_SchedContext_Bind
```c
seL4_SchedContext_Bind(schedcontext, cap);
// cap = TCB (или notification) — привязать к SC.
```

### seL4_TCB_SetSchedParams (MCS, manual_label `tcb_setschedparams_mcs`)
```c
seL4_TCB_SetSchedParams(tcb, schedcontext, priority, mcp);
```

## 6. Ключевые отличия non-MCS → MCS

1. **Fault handler**: endpoint (`TCBConfigure` с `fault_ep`) → **Reply-объект**.
2. **TCBConfigure**: 8 параметров (с fault_ep) → **7** (без fault_ep).
3. **Reply → ReplyRecv** (reply + recv в одном syscall).
4. **Scheduling contexts**: новые объекты + `SchedControl` + `SchedContext_Bind`.
5. Root-задача ловит fault через **ReplyRecv**, а не `Recv` на fault-endpoint.

## 7. План оставшейся работы

✅ **Все шаги выполнены и валидированы в QEMU.** Итоговая реализация (с
уточнениями против изначального плана):

- **Шаг 2** — `schild_sel4_syscalls.S`: `reply` → `schild_sel4_replyrecv`
  (SysReplyRecv=-2, reply cap в R12); `Recv` получил reply-аргумент (R12);
  добавлены `schild_sel4_wait` (SysWait=-9), `schild_sel4_nbwait` (SysNBWait=-10),
  `schild_sel4_reply_only` (SysSend к reply-капу, для crash-containment).
- **Шаг 3** — `schild_sel4_syscall.ads`: `Recv`→`Wait`, `NBRecv`→`NBWait`,
  удалён неиспользуемый `Reply`; добавлены `SchedControl_ConfigureFlags` и
  `SchedContext_Bind`. `schild_sel4_bootinfo.ads`: добавлено поле
  `SchedControl_Start/End` (MCS-сдвиг `untyped` на 16 байт).
- **Шаг 4** — `schild_sel4_syscall.adb`: для каждого потока создаются SC
  (`size_bits=7`, >= `seL4_MinSchedContextBits`) и Reply-объект, затем
  `SchedControl_ConfigureFlags` (budget=period=5000 мкс) + `SchedContext_Bind`.
  Fault-обработчик ставится через **TCBSetSpace (MCS, label 11)** — в MCS
  fault_ep резолвится в CSpace вызывающего и копируется в TCB, поэтому для
  NetServer badged-копия (0xE2) минтится в **root**-CSpace (slot 214), а не в
  CSpace NetServer'а. (Вместо TCBConfigure MCS + TCB_SetSchedParams
  использованы TCBSetSpace + TCBSetIPCBuffer + SchedContext_Bind — функционально
  эквивалентно и меньше переписываний.)
- **Шаг 5** — C-шимсы: цикл `Recv(src, reply)` → `ReplyRecv(src, info, reply)`;
  reply-объект передаётся через новые глобальные `net/mls/config_reply_cptr`.
- **Шаг 6** — MCS-ядро пересобрано с `CONFIG_PRINTING=1` (иначе ядро молчит),
  `run_tests.sh` даёт **PASS по всем 12 маркерам** (MLS, NetServer, IRQ, DMA,
  fault-containment badge=0xE2 + HM-restart).

## 8. Файлы для изменения

| Файл | Строк | Что |
|---|---|---|
| `tools/sel4/src/schild_sel4_syscalls.S` | 141 | reply→ReplyRecv + новые stub'ы |
| `tools/sel4/src/schild_sel4_ipc.c` | 408 | Call/Reply обёртки |
| `tools/sel4/src/schild_sel4_syscall.ads` | 328 | объявления |
| `tools/sel4/src/schild_sel4_syscall.adb` | 863 | Init_Fault_Handler, Launch_* |
| `tools/sel4/src/netserver.c` / `mls_server.c` / `config_daemon.c` | — | replyrecv |

## 9. Команды

```bash
# собрать MCS-ядро (если нужно пересобрать)
cd src/schild_core
KERNEL_MCS=ON scripts/build_sel4_kernel.sh

# собрать seL4-ветку (root task)
SEL4_PRIMARY=1 ./build.sh

# валидация QEMU
SKIP_BUILD=1 SEL4_PRIMARY=1 ./scripts/run_tests.sh
```

## 10. Важные замечания

- `kernel.elf` — в `.gitignore` (бинарник не коммитится). MCS-ядро **уже установлено**.
- Исходники seL4 — `/tmp/seL4` (клонируются `build_sel4_kernel.sh`; API — в
  `libsel4/include/interfaces/object-api.xml`, `.../sel4/syscalls_mcs.h`).
- x86_64 MCS **собирается**, но формально верифицировано слабее, чем ARM MCS —
  при необходимости отразить в `ASSURANCE.md`.
