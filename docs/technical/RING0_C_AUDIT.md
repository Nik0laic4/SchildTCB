# Schild TCB — Ring-0 C Audit (C1)

**Version:** v0.1 (draft) | **Date:** 2026-11-08
**Статус:** Блок 3, третий пункт (после H87-дизайна и AS6-спеки). Аудит, не рефакторинг.

---

## 1. Назначение

C1 (THREAT_MODEL T8b/R9): ring-0 C — **не содержит** containment (это Ring 3
механизм). Баг в ring-0 C = паника ядра или произвольное исполнение в Ring 0.
Задача — (а) зафиксировать, что именно в ring-0 C, (б) что можно вынести в
Ring 3 (после H87 ELF loader), (в) остальное пометить как **trusted (AS8)**.

## 2. Инвентарь

| Файл | Строк | Роль | Привилегия |
|---|---|---|---|
| `boot.S` | 601 | 32-bit entry, identity paging, long-mode handoff, SSE/FPU enable | **обязательно ring-0** (до ядра) |
| `src/hw_io.c` | 43 | `outb`/`inb` (порт I/O x86_64) | **ring-0** (порт I/O; Ring 3 требует IO-bitmap) |
| `src/interrupt_handlers.c` | 323 | IDT init, APIC/LAPIC/IOAPIC, PIT, PIC remap, `sti/hlt/cli`, i8042 reset | **ring-0** (IDT/APIC привилегированы) |
| `src/runtime_stubs.c` | 521 | C-runtime заглушки (`malloc/free`=no-op, panic, secondary stack), UART, framebuffer, `memcmp`, trampoline, `wbinvd/clflush` | смешанно (см. §3) |

## 3. Классификация

### 3.1 Trusted, остаётся в ring-0 (AS8)

- **`boot.S`** — доверенный стартовый путь (Multiboot2 → long mode). Не выносим.
- **`interrupt_handlers.c`** — IDT/APIC/IOAPIC/PIT/PIC: это прерывания и таймеры,
  структурно ring-0. Доступ через MMIO (0xFEE00000) привилегирован.
- **`hw_io.c`** — `inb`/`outb`: порт I/O. В Ring 3 доступен только через
  IO-bitmap TSS (seL4 не экспонирует порт-I/O даемонам; MSI/MMIO — вместо портов).
- **`runtime_stubs.c` panic/reset** — `__gnat_last_chance_handler`, i8042 reset:
  последняя линия защиты от wedge, должна быть ring-0.

### 3.2 Кандидаты на вынос в Ring 3 (после H87)

- **UART helper** (`schild_uart_puts/putln`) — если UART отдать даемону-драйверу.
- **Framebuffer** (`schild_fb_*`) — если FB отдать даемону-драйверу.
- **`memcmp`/`memset`-подобные** — чистые функции, уже в Ring 3 как часть runtime.
- **Runtime-заглушки** (`malloc/free`=no-op, `abort`, secondary stack) — при
  появлении полноценного Ring 3 runtime (H87) заменяются на реальные.

**Вывод:** выносимое — это **утилиты и runtime-клей**, не привилегированный
механизм. Привилегированный слой (boot/IDT/APIC/port-I/O) остаётся ring-0
и помечается **trusted (AS8)**. Полный «0 строк ring-0 C» — не цель и не
достижим без переписывания boot/IDT на Ada/SPARK (отдельная задача).

## 4. Что даёт вынос (после H87)

- Уменьшает TCB: меньше доверенных строк в Ring 0.
- Даже до выноса — документация (этот файл) делает trust-границу явной:
  в THREAT_MODEL §9 уже перечислен ring-0 C; здесь — построчный инвентарь.

## 5. Residuals

- Ring-0 C остаётся **trusted, не proved** (AS8) до переписывания (если будет).
- `schild_sel4_loader.c` / `schild_sel4_boot.c` (seL4 root-task build) — отдельный
  слой, описан в H87/AS6, не в этом аудите.
- IO-bitmap TSS для порт-I/O даемонам — out of scope (seL4 x86_64 MCS не даёт
  готового пути; драйверы используют MMIO/MSI).
