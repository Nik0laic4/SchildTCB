# Schild TCB — Ring-0 C Audit (C1)

**Version:** v0.1 (draft) | **Date:** 2026-11-15
**Scope:** классификация ring-0 trusted C (bare-metal профиль) — что можно вынести
в Ring 3, что остаётся AS8-trusted. Консолидирует `THREAT_MODEL.md` R9/T8b/C-§.

## 1. Что входит в ring-0 C (bare-metal)

| Файл | Строк | Роль |
|---|---|---|
| `boot.S` | 601 | Multiboot2 → x86_64 Long Mode → Ada kernel (bootstrap) |
| `interrupt_handlers.c` | 323 | IDT exception handlers + APIC EOI/init + system reset + raw UART (debug) |
| `runtime_stubs.c` | 521 | UART/framebuffer/debug-render + GNAT Rcheck (panic→reset) + MMIO map + phys write |
| `hw_io.c` | 43 | `outb`/`inb` (port I/O) |

Все четыре — ring-0, memory-unsafe (C), runtime-tested only (`THREAT_MODEL` R9).

## 2. Классификация

### 2.1 Остаётся ring-0 (AS8 trusted) — не выносится

- **`boot.S`** — bootstrap: GDT/IDT/paging/Long-Mode до появления Ring 3. Переносу не подлежит.
- **`interrupt_handlers.c` → IDT/APIC** — `__attribute__((interrupt))` exception handlers
  (`eDE..eDF`, PF, GP, …) + `apic_eoi`/`apic_init`. Работают на interrupt-стеке, привилегированы.
- **`runtime_stubs.c` → GNAT Rcheck** (`__gnat_rcheck_*`, `__gnat_last_chance_handler`,
  `__gnat_raise_exception`) — panic → `system_reset()`. Это контракт «fail-stop», не выносится.
- **`runtime_stubs.c` → `schild_map_mmio_2mb` / `schild_phys_write64`** — манипуляция page-table
  и физические записи (MMIO). Ring-0 по определению.

### 2.2 Выносится в Ring 3 (уменьшает ring-0 поверхность)

- **UART** — `schild_uart_puts`/`schild_uart_putln` (`runtime_stubs.c`) и raw-UART в
  `interrupt_handlers.c`. Комментарий: raw-UART в interrupt-handlers — дублирующий debug-путь,
  можно удалить после перевода на единственный UART-канал.
- **Framebuffer** — `schild_fb_init`/`putpixel`/`scroll` (`runtime_stubs.c`), MMIO-доступ.
- **Debug render** — `schild_debug_render` (`runtime_stubs.c`), буфер-в/буфер-из.
- **Port I/O** — `outb`/`inb` (`hw_io.c`, 43 строки): в Ring 3 возможен через TSS I/O bitmap
  (разрешить только порты UART 0x3F8/0x3FD, 0x64) либо оставить AS8-trusted (43 строки,
  без арифметики указателей — низкий риск).

## 3. Целевая архитектура (после C1)

```
ring 0:  boot.S + IDT/APIC + Rcheck(fail-stop) + mmio-map/phys-write   [AS8 trusted, ~миним.]
ring 3:  UART driver + framebuffer driver + debug render               [isolated, memory-safe Ada]
```

## 4. Оценка влияния и порядок

1. **✅ (v0.50)** — перевести raw-UART debug на единый канал (удалить дубль из
   `interrupt_handlers.c`), не меняя ring-0 семантики. Сделано: `schild_uart_putc_raw`
   экспортирован из `runtime_stubs.c`, `interrupt_handlers.c` делит его (fail-stop lock-free).
2. **Premature** — ring-3 UART/framebuffer драйвер: **bare-metal профиль не имеет ring-3
   пользовательского пространства**, а в seL4-профиле UART уже в ring-3 (root task).
   Отложено до появления ring-3 в bare-профиле; для seL4 это отдельная задача.
3. **Port I/O** — либо TSS I/O bitmap, либо оставить AS8 (43 строки). При отсутствии
   ring-3 в bare — оставить AS8.

Каждый шаг — отдельный коммит с gates (build + run_tests + host-KAT).
