# Session handoff — ARM64 virtio-net + изоляция (2026-10-24)

> Документ для чистой новой сессии. Прочитать целиком, затем продолжать с
> раздела «Осталось».

## 1. Git-состояние

- Ветка **`arm64`** = `46c79aa` (1 коммит впереди `origin/arm64` = `fc1fc95`), **не запушена**.
- `master` = `fc1fc95` (= `origin/master`). Рабочее дерево чистое.
- Репозиторий: `/home/null/Рабочий стол/SchildTCB`.

Коммиты (по порядку):

| SHA | Что |
|---|---|
| `efe9abf` | Кольцо дескрипторов (RX-пул + ротация TX) |
| `54d1411` | IRQ через seL4 Notifications (неблокирующий poll) |
| `cdc1ee9` | IRQ waiter-тред (блокирующий `seL4_Wait`) |
| `7aea82a` | Разделение драйвер (`virtio_net.h`) / тест (`net_test.c`) |
| `1f425db` | Child-домен (свой CSpace + кросс-доменный signal) |
| `5ac4ad1` | Драйвер IRQ-пути + протокол в изолированном child-домене |
| `d6b3c8a` | Документация: актуализация статуса + session handoff |
| `da7fdae` | Child-процесс в своём VSpace (отдельный page table + ELF-загрузчик) |
| `fc1fc95` | Документация: актуализация process-isolation статуса |
| `46c79aa` | virtio-net драйвер + протокол в ELF-child (отдельный VSpace) |

## 2. Что сделано и валидировано (QEMU `-M virt`, SLIRP + hostfwd)

Полный сетевой путь под seL4 на AArch64 работает end-to-end:

```
virtio-net MAC = 52:54:00:12:34:56
[body] SchildTCB-body
[dns] 8.6.112.0
[irq] 49
virtio-net: OK (own VSpace + ELF child)
```

- Стек: ARP → ICMP → DHCP → TCP-клиент/HTTP → TCP-сервер → DNS.
- Кольцо дескрипторов: split-ring, RX-пул (4 буфера, рециклинг через used ring) + ротация TX; `avail_idx`/`used_idx` монотонны, выбор буфера по `used->ring[i].id`.
- IRQ: `IRQControl_Get` → Notification (badge 79) → waiter-тред (`seL4_Wait`) → Ack → signal main-тред.
- Изоляция: драйвер IRQ-пути + протокол выполняются в **child-домене со своим CSpace** (16-слотовый CNode: self CNode + RAM untyped + IRQ handler + VSpace + result notification). Device (MMIO/DMA/queues) инициализирует root-задача. VSpace — **общий** (см. следующий пункт).
- **Полная process-изоляция**: root создаёт **отдельный VSpace** (VSpaceObject + ASID pool + ASID assignment), загружает **дочерний ELF** с драйвером + протоколом и передаёт device MMIO + DMA в VSpace ребёнка — net-драйвер + протокол выполняются в ELF-child (`virtio-net: OK (own VSpace + ELF child)`).

## 3. Архитектура (файлы)

| Файл (`src/schild_core/arm64/ada/`) | Назначение |
|---|---|
| `sel4_mmio.c` | Платформа (сырые syscall-шиммы, retype, MMIO-маппинг) + драйвер `virtio_net_*` + child-spawn + VSpace/ELF-загрузчик (`vspace_new`, `elf_load_segment`, `schild_elf_child_test`) |
| `virtio_net.h` | Публичный API драйвера: `init`/`tx_buffer`/`tx_send`/`rx`/`rx_done`/`irq_count` |
| `net_test.c` | Протокольный стек (build/parse) + `schild_virtio_net_run_test` (без init) |
| `schild_arm_root_task.adb` | Ada/SPARK root-задача (вызывает `schild_net_child_test` + `schild_elf_child_test`) |
| `build_root.sh` | Сборка root-задачи + child ELF (`child.elf`) + валидация обоих |
| `child_main.c` | Тело child-процесса (DebugPutChar + signal slot 0) |
| `child_start.S` | Entry child-процесса (стек в своём .bss) |
| `child_linker.ld` | Лейаут child-процесса (RX/RW сегменты @ 0x400000) |

Ключевые функции:

- `virtio_net_init_device()` — MMIO/DMA/queues/RX-пул/DRIVER_OK (root).
- `virtio_net_init_irq(struct irq_ctx *)` — параметризованный IRQ-путь (notification + waiter-тред в заданном CSpace-контексте).
- `schild_spawn_net_child()` — грант капов ребёнку + запуск TCB.
- `schild_net_child_main()` — entry ребёнка: IRQ-init + протокол + signal результата.

## 4. Ключевые константы seL4 (выведены из ядра/QEMU, не из libsel4)

| Константа | Значение | Примечание |
|---|---|---|
| virtio-net IRQ | **79** | GIC SPI 47 = 32+47 (slot 31 `0x0a00_3e00`, `NUM_PPI=32`) |
| root CNode depth | **64** (wordBits) | radix=13, guard=wordBits−13 (boot.c:280) |
| CNode retype `size_bits` | **radix** (не radix+SlotBits) | `getObjectSize` сам добавляет `SlotBits` |
| Invocation labels | UntypedRetype=1, TCBWriteRegisters=3, TCBConfigure=5, CNodeMint=21, IRQIssueIRQHandler=26, IRQAckIRQ=27, IRQSetIRQHandler=28, ARMPageMap=40 | non-MCS |
| Labels (VSpace/ASID) | ARMPageTableMap=38, ARMPageTableUnmap=39, ARMPageMap=40, ARMPageUnmap=41, ARMASIDControlMakePool=47, ARMASIDPoolAssign=48 | non-MCS |
| `seL4_NotificationObject`=3 (bits=5), `seL4_TCBObject`=1 (bits=11), `seL4_CapTableObject`=4, `seL4_SmallPageObject`=7 | | non-MCS AArch64 |
| `seL4_ARM_VSpaceObject`=6 (bits=12), `seL4_ARM_HugePageObject`=5, `seL4_ARM_LargePageObject`=8 (bits=21), `seL4_ARM_PageTableObject`=9 (bits=12) | | non-MCS AArch64 |
| `seL4_CapIRQControl`=4, `seL4_CapInitThreadCNode`=2, `seL4_CapInitThreadVSpace`=3, `seL4_CapASIDControl`=5 | | фикс. слоты root CNode |
| `seL4_CapRights` | bit0=Write, bit1=Read (ReadOnly=2, ReadWrite=3) | права страниц |
| VM attributes | PageCacheable=1, ExecuteNever=4 | `seL4_ARM_VMAttributes` |
| Syscall ids | Call=-1, Send=-3, Recv=-5, NBRecv=-8, DebugPutChar=-9 | |

### Gotchas (важно для новой сессии)

1. **CNode `UntypedRetype`**: `size_bits` = radix (а не `radix + seL4_SlotBits`); ядро само считает `getObjectSize = SlotBits + radix`.
2. **4 KiB small-page map** требует промежуточной page table (которой нет) → `seL4_FailedLookup`; используй **2 MiB block-mapping** (`retype_large_page` + `ARMPageMap`).
3. **Ребёнку нужен собственный IPC-буфер** (иначе `UntypedRetype` с MR4/MR5 усекается: «No IPC buffer for thread»). Здесь — внутри 2 MiB stack-страницы, `ipc_buf = 0x900000` в entry ребёнка.
4. **non-MCS `TCB_Configure`** берёт `fault_ep` первым MR (len=4), в отличие от MCS-варианта.
5. **`seL4_Wait`/`seL4_NBRecv`** возвращают badge в x0; на AArch64 `capRegister == badgeRegister == 0` (x0).
6. IRQ-notification badge 79 нужен только для NBRecv-различения; при блокирующем `seL4_Wait` badge не критичен.
7. **VSpace AArch64 = 4 уровня (48-bit)**: VSpaceObject (root, 512 слотов) → 3×PageTableObject (L2/L1/L0) → small page (4 KiB). Для large page (2 MiB) нужны только L2+L1. `ARMPageTableMap` ставит таблицу на уровень, где остановился walk `lookupPTSlot`.
8. **`ipc_buf` — общая переменная** (root и net-child в одном ELF): net-child переключает её на `CHILD_IPC_BUF_VA`; root обязан восстановить `ipc_buf = BootInfo.ipcBuffer` перед своими syscalls.
9. **ASID pool** создаётся из 4 KiB untyped: `ARMASIDControlMakePool` (EC[0]=untyped, EC[1]=root CNode, MR[0]=slot, MR[1]=depth), затем `ARMASIDPoolAssign` (EC[0]=vspace). `seL4_CapASIDControl` = слот 5.

## 5. Как собирать и валидировать

Инструменты: `aarch64-linux-gnu-gcc-14`/`gnatmake-14`/`ld`/`strip`, `qemu-system-aarch64`, `ninja`/`cmake`, `dtc`. Проект seL4 — `/home/null/sel4proj` (уже собран, `griddle` для `qemu-arm-virt`, aarch64, non-MCS).

```bash
# 1. Собрать ELF root-задачи (Ada + C)
cd src/schild_core/arm64/ada && ./build_root.sh

# 2. Внедрить как rootserver и пересобрать elfloader
aarch64-linux-gnu-strip -o /home/null/sel4proj/build/elfloader/rootserver root_task.elf
cd /home/null/sel4proj/build && ninja

# 3. Прогнать полный тест (харнесс: host HTTP 8080 + hostfwd TCP 8081 + DNS)
python3 /tmp/run_net_test.py
```

Харнесс `/tmp/run_net_test.py` (не в репозитории — воссоздать):
- HTTP-сервер на `127.0.0.1:8080` (отдаёт `SchildTCB-body` одним сегментом).
- TCP-клиент на `127.0.0.1:8081` (hostfwd) с задержкой ~5 c.
- QEMU: `-M virt,gic-version=2 -cpu cortex-a53 -m 2G -netdev user,id=n0,hostfwd=tcp::8081-:8081 -device virtio-net-device,netdev=n0,mac=52:54:00:12:34:56 -kernel images/sel4test-driver-image-arm-qemu-arm-virt`, serial → файл.

Ожидаемый маркер успеха: `virtio-net DNS: OK (child)`.

### Среда

- **`libarchive-c`** нужно в активном venv для пересборки elfloader (скрипт `shoeshorn.py`; системная `libarchive.so.13` уже есть): `pip install libarchive-c`. **Зафиксировать в окружении сборки** (пока не сделано).

## 6. Известные ограничения / долг

- **VSpace**: net-драйвер + протокол теперь выполняются в ELF-child с отдельным VSpace (`virtio-net: OK (own VSpace + ELF child)`); device MMIO + DMA передаются в VSpace ребёнка.
- **Параметры захардкожены**: MAC `52:54:00:12:34:56`, guest IP `10.0.2.15` (несмотря на парсинг DHCP), шлюз `10.0.2.2`, DNS `10.0.2.3`, порты 8080/8081.
- **TCP не настоящий**: полученные данные не ACK-аются («we never ACK»), нет FIN/teardown → ретрансмитный шум `[irq]`.
- **Сырой syscall-слой** (hand-rolled labels/offsets) вместо libsel4/vka.
- **Харнесс ручной** (host-сервисы + SLIRP), нет CI-повторяемости; SLIRP нестабилен по IRQ.
- virtio-net — **только QEMU**; на Pi 4 сетевая карта — **GENET** (другой драйвер).

## 7. Осталось (по приоритету)

1. **Минимальный TCP ACK** полученных данных — уберёт ретрансмитный шум.
2. **Повторяемая валидация** — скрипт + `-netdev socket`/tap вместо ручного
   SLIRP-харнесса.
3. **Процесс:** запушить `arm64` (1 коммит `46c79aa` впереди origin), решить
   судьбу `master`, зафиксировать `libarchive-c`.
4. **Целевое железо:** драйвер **GENET** (Pi 4) вместо virtio-net.

