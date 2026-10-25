# Schild TCB — Требования и трассируемость: ARM64 net-модуль (пилот)

**Version:** v1.0 | **Date:** 2026-10-25
**Scope:** `src/schild_core/arm64/ada/` — seL4 AArch64 + virtio-net + изоляция + валидация.
**Цель:** пилот формата «требование → дизайн → код → тест» как шаг к DO-178C / DO-333 /
Common Criteria (см. `DEVELOPMENT_VECTORS.md`).
**Связанные:** `ROADMAP.md` (§6), `SESSION_ARM64_NET.md`.

> Каждое требование механически проверяемо (маркер в UART-выводе QEMU, в сборке или в
> харнессе). Никаких «агрегатных» утверждений без per-component проверки.

---

## 1. Схема идентификаторов

| Префикс | Уровень |
|---|---|
| `ARM64-SYS-` | системное требование (направление целиком) |
| `ARM64-HLR-` | software high-level requirement (что делает софт) |
| `ARM64-LLR-` | software low-level requirement (производное, близко к коду) |

---

## 2. Системные требования (SYS)

| ID | Требование | Верификация |
|---|---|---|
| `ARM64-SYS-1` | Полный цикл seL4 AArch64: elfloader → ядро → root task → вывод по UART | маркер `==== Schild TCB: Ada/SPARK seL4 root task (AArch64) ====` |
| `ARM64-SYS-2` | virtio-net драйвер + полный протокольный стек работают под seL4 | маркер `virtio-net: OK (own VSpace + ELF child)` |
| `ARM64-SYS-3` | Сетевой драйвер + протокол выполняются в изолированном child-процессе с отдельным VSpace | тот же маркер + `[irq] N` |
| `ARM64-SYS-4` | Валидация повторяема и детерминирована (без SLIRP-зависимостей) | `[harness] PASS`, `[dns] 1.2.3.4` (фиксированный IP) |

---

## 3. High-level требования (HLR)

| ID | Требование |
|---|---|
| `ARM64-HLR-1` | Root task стартует на AArch64, печатает через `seL4_SysDebugPutChar` и завершает тест корректно |
| `ARM64-HLR-2` | virtio-mmio устройство обнаруживается, маппится, читается MAC |
| `ARM64-HLR-3` | Протокольный стек: ARP → ICMP echo → DHCP → TCP-клиент/HTTP → TCP-сервер → DNS |
| `ARM64-HLR-4` | IRQ-путь драйвера выполняется в child-домене со своим CSpace (уведомления + waiter-тред) |
| `ARM64-HLR-5` | Полная process-изоляция: net-драйвер + протокол в ELF-child с отдельным VSpace |
| `ARM64-HLR-6` | Принятые TCP-данные подтверждаются ACK (нет ретрансмитного шума) |
| `ARM64-HLR-7` | Валидация автоматизирована: сборка → inject → QEMU → проверка маркера, exit 0/1 |

---

## 4. Low-level требования (LLR)

| ID | Требование |
|---|---|
| `ARM64-LLR-2.1` | MMIO маппится через `UntypedRetype` (2 MiB large page) + `ARMPageMap` в VSpace |
| `ARM64-LLR-3.1` | Split-virtqueue: RX-пул буферов + ротация TX, рециклинг через used-ring по `id` |
| `ARM64-LLR-4.1` | IRQ: `IRQControl_Get` → badged Notification → waiter-TCB (`seL4_Wait`) → `IRQHandler_Ack` → signal |
| `ARM64-LLR-5.1` | Создание VSpace: retype `VSpaceObject` + `ARMASIDControlMakePool` + `ARMASIDPoolAssign` |
| `ARM64-LLR-5.2` | Иерархия page table (L2/L1/L0) + загрузка `PT_LOAD` (код RX / данные RW+NX) |
| `ARM64-LLR-5.3` | Child CSpace: self CNode + RAM untyped + IRQ handler + VSpace + result ntfn (badge 42) |
| `ARM64-LLR-6.1` | Pure-ACK сегмент (флаги `ACK`, `ack = seq + len`) после принятых данных |

---

## 5. Матрица трассировки

| ID | Дизайн (файл) | Код (функция) | Тест (маркер) |
|---|---|---|---|
| `ARM64-SYS-1` / `HLR-1` | `root_start.S`, `sel4_stubs.c`, `schild_arm_root_task.adb` | `_sel4_start` → `_ada_schild_arm_root_task`; `schild_sel4_debug_putchar` | `==== Schild TCB ... ====`, `Hello from Ada (seL4 AArch64 root task)!` |
| `ARM64-HLR-1` | `build_root.sh` | — | сборка: `svc #0` present, `_sel4_start` present, Ada entry present |
| `ARM64-HLR-2` | `sel4_mmio.c` | `schild_map_mmio`, `schild_virtio_mac` | `virtio-net MAC = 52:54:00:12:34:56` |
| `ARM64-LLR-2.1` | `sel4_mmio.c` | `retype_large_page`, `map_page` | (покрывается `HLR-2`) |
| `ARM64-HLR-3` | `net_test.c` | `build_arp_request`, `build_tcp_frame`, `parse_tcp`, `build_dhcp_frame`, `parse_dhcp_offer`, `build_dns_frame`, `parse_dns_reply`, `schild_virtio_net_run_test` | `[body] SchildTCB-body`, `[dns] 1.2.3.4` |
| `ARM64-LLR-3.1` | `sel4_mmio.c` | `setup_queue`, `rx_post`, `rx_poll`, `rx_frame`, `virtio_net_tx_send` | (покрывается `HLR-3`) |
| `ARM64-HLR-4` | `sel4_mmio.c` | `virtio_net_init_irq`, `irq_waiter`, `irq_poll` | `[irq] N` |
| `ARM64-LLR-4.1` | `sel4_mmio.c` | `sel4_irq_control_get`, `sel4_irq_handler_set_ntfn`, `sel4_irq_handler_ack`, `sel4_wait` | (покрывается `HLR-4`) |
| `ARM64-HLR-5` | `sel4_mmio.c`, `child_start.S`, `child_linker.ld` | `vspace_new`, `map_page_table`, `elf_load_segment`, `schild_net_elf_child_test`, `schild_net_elf_child_main` | `virtio-net: OK (own VSpace + ELF child)` |
| `ARM64-LLR-5.1..5.3` | `sel4_mmio.c` | `vspace_new`, `map_page_table`, `map_frame`, `sel4_cnode_mint`, `sel4_tcb_configure` | (покрывается `HLR-5`) |
| `ARM64-HLR-6` | `net_test.c` | (ACK после HTTP-ответа) | `[ack]` |
| `ARM64-LLR-6.1` | `net_test.c` | `build_tcp_frame` (флаги `0x10`, `ack = seq2 + pl2`) | `[ack]` |
| `ARM64-HLR-7` | `run_net_test.py`, `net_peer.py` | `run_net_test.py` (build→inject→QEMU→poll), `net_peer.py` (ARP/ICMP/DHCP/TCP/DNS) | `[harness] PASS: virtio-net E2E in an ELF child (own VSpace)` |

---

## 6. Замечания (пилот)

- Формат «требование → дизайн → код → тест» продемонстрирован на ARM64 net-модуле как
  пилот. Дальнейший шаг (по `DEVELOPMENT_VECTORS.md`): **расставить ID-комментарии в коде**
  (например, `/* ARM64-LLR-5.1: VSpace creation */`) и добавить **покрытие кода** в CI.
- Механические проверки уже существуют (маркеры + `run_net_test.py` + валидация ELF в
  `build_root.sh`); этот документ лишь связывает их с требованиями.
- **Покрытие кода (пилот)**: `build_proto_test.sh` + `proto_test.c` — host-side юнит-тест
  чистой протокольной логики `net_test.c` с `gcov` (покрывает `HLR-3`/`LLR-3.1`,
  `HLR-6`/`LLR-6.1`). Гоняется в CI (джоба `build-arm64`).
