# Schild TCB — Дизайн драйвера GENET (Raspberry Pi 4) — конспект

**Version:** v1.0 | **Date:** 2026-10-25
**Status:** конспект дизайна (без кода) — подготовка к приходу железа Pi 4.
**Референсы:** Linux `drivers/net/ethernet/broadcom/genet/bcmgenet.{c,h}` (GPL-2.0),
`arch/arm/boot/dts/broadcom/bcm2711.dtsi`, паттерн DDE из L4Re.
**Связь:** `ROADMAP.md` §6.2, `DEVELOPMENT_VECTORS.md`.

> GENET — сетевая карта Pi 4. QEMU её **не эмулирует**, поэтому код пишем после получения
> железа; этот документ — скелет драйвера, чтобы к тому моменту остался только порт под seL4.

---

## 1. Что такое GENET

Broadcom GENET (Gigabit Ethernet) — DMA-дескрипторный Ethernet-контроллер BCM2711.
Программная модель принципиально та же, что у virtio-net: **кольца дескрипторов в DMA-памяти
+ MMIO-регистры + прерывание**. Поэтому драйвер реализуется как **drop-in замена `virtio_net.h`**
(тот же API `init`/`tx_buffer`/`tx_send`/`rx`/`rx_done`/`irq_count`), а протокольный стек и
изоляция остаются без изменений.

## 2. Ключевые аппаратные факты (проверено по Linux/DTS)

| Параметр | Значение |
|---|---|
| MMIO base (bus) | `0x7d580000`, размер `0x10000` |
| MMIO base (ARM phys) | `0xfd580000` (через `soc ranges 0x7c000000→0xfc000000`) |
| IRQ | GIC SPI **157** (`genet`) + **158** (`genet-parent`), level-high |
| IRQ в seL4 | `32 + 157 = 189` (основной), `190` (parent) |
| seL4 `RPI4_MEMORY` | **8192** (8 ГБ) — default для реального Pi 4 |
| DMA-окно | **нижний 1 ГБ** (`dma-ranges = <0xc0000000 0 0x40000000>`); остальная ОЗУ GENET не видит |
| Дескрипторов на кольцо | **256** (`TOTAL_DESC`) |
| Размер дескриптора | **12 байт** (3 слова) |

**Формат DMA-дескриптора** (RX и TX одинаковый):

| Смещение | Поле | Назначение |
|---|---|---|
| `0x00` | `length_status` | длина буфера + флаги статуса |
| `0x04` | `address_lo` | младшие 32 бита физического адреса буфера |
| `0x08` | `address_hi` | старшие 32 бита (GENET v4+) |

**Register-блоки** (точные смещения брать из `bcmgenet.h` при реализации):

- `UMAC` — MAC-регистры (режим, MAC-адрес, статистика).
- `GENET sys` (`GENET_SYS_OFF`) — системные/сброс/версия.
- `EXT` (`GENET_EXT_OFF`) — расширенные (питание, PHY reset).
- `RBUF` (`GENET_RBUF_OFF`) — RX buffer control (сброс/флаш).
- `TBUF` — TX buffer control.
- `DMA` (`rdma_offset`/`tdma_offset`) — кольца: ring address, size, read/write указатели,
  interrupt mask/status.
- `INTRL2` (`GENET_INTRL2_0_OFF`/`_1_OFF`) — второй уровень контроллера прерываний.
- `HFB` — аппаратный фильтр кадров.

**RSB (Receive Status Block)** — 64-байтовый блок статуса, который HW пишет **перед** каждым
принятым кадром в RX-буфер (`struct status_64`, `GENET_RSB_PAD = 66`).

## 3. Архитектура драйвера (повторяет `virtio_net.h`)

Новый файл `genet.c` + `genet.h` реализует **тот же публичный API**, что `virtio_net.h`:

| Функция (`virtio_net.h`) | Эквивалент GENET |
|---|---|
| `virtio_net_init()` | `genet_init()` — map MMIO, alloc DMA, кольца, reset, enable |
| `virtio_net_tx_buffer()` | `genet_tx_buffer()` — следующий TX-дескриптор |
| `virtio_net_tx_send(len)` | `genet_tx_send(len)` — записать дескриптор + kick TDMA |
| `virtio_net_rx()` | `genet_rx()` — ждать IRQ, отдать кадр за RSB |
| `virtio_net_rx_done()` | `genet_rx_done()` — вернуть буфер в кольцо (продвинуть consumer) |
| `virtio_net_irq_count()` | `genet_irq_count()` |

Это даёт **нулевые изменения** в `net_test.c` (протокольный стек) и в
`schild_net_elf_child_test`/`schild_net_elf_child_main` (изоляция). Меняется только: что
драйвер компилируется из `genet.c` вместо `virtio_net_*`, и что device/DMA handoff передаёт
GENET MMIO (`0xfd580000`) + DMA-кольца + IRQ (189).

## 4. Инициализация / RX / TX / IRQ (высокоуровнево)

По `bcmgenet.c` (упрощённо, без PHY/MDIO для первого шага):

1. **Сброс**: `UMAC` reset → `GENET` soft reset → сброс RBUF/TBUF.
2. **DMA-кольца**: выделить 2 MiB-фрейм под дескрипторы + буферы RX/TX; записать адреса колец
   в DMA-регистры; 256 дескрипторов на кольцо.
3. **RX-пул**: заполнить RX-дескрипторы (адрес буфера + длина), выставить read/write указатели.
4. **MAC**: включить UMAC (скорость/дуплекс — для Pi 4 фиксированный link через MDIO или
   `fixed-link`), записать MAC-адрес.
5. **DMA + IRQ**: включить RDMA/TDMA, разрешить прерывания в `INTRL2`.
6. **RX-прерывание**: прочитать `INTRL2` status → снять маску → обработать принятые
   дескрипторы (кадр после RSB) → продвинуть consumer-указатель → Ack IRQ.
7. **TX**: записать дескриптор (адрес+длина) → kick TDMA → ждать used/consume.

## 5. Интеграция в существующую изоляцию

Полностью повторяет текущую схему virtio-net (валидирована):

- **Root** инициализирует GENET (MMIO + DMA + кольца + DRIVER_OK-эквивалент).
- **Child-процесс** (отдельный VSpace + ELF) получает GENET MMIO + DMA + IRQ через handoff
  (unmap/remap), re-attach состояния и гоняет протокольный стек.
- Единственное отличие от virtio-net: адрес устройства `0xfd580000` и IRQ `189`.

## 6. Что уточнить при реализации

- Точные смещения register-блоков (`GENET_*_OFF`, DMA ring regs, `INTRL2`) — из `bcmgenet.h`.
- PHY/MDIO: на Pi 4 — внутренний PHY; для первого шага можно `fixed-link` (без autoneg),
  позже — MDIO.
- `dma-ranges`: GENET может адресовать только **нижний 1 ГБ** (`ZONE_DMA`,
  `dma-ranges = <0xc0000000 0 0 0x40000000>`). Для **8 ГБ** это критично: DMA-фрейм
  (кольца + RX/TX-буферы) выделять из физического диапазона `< 0x40000000`, иначе
  контроллер не дотянется. В `sel4_mmio.c` нужен «выделить untyped из нижнего 1 ГБ»
  (фильтр по `paddr < 0x40000000`).
- 64-битные адреса: буферы всегда в нижнем 1 ГБ, поэтому `address_hi = 0`; достаточно
  `address_lo` (32 бита).
