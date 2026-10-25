# ARM64 (Raspberry Pi 4B) — порт

## Статус
✅ Полный цикл seL4 AArch64 работает в QEMU: **elfloader → ядро → root task → вывод по UART** (`Hello, Schild TCB (ARM64 root task)!`).

## Структура
- `apps/hello/` — минимальная C root-задача (печать через `seL4_DebugPutChar`, syscall -9).
- `src/` — ранние эксперименты (start.S + debug_io.c, прямая линковка — **не работает без elfloader**, оставлено как история).
- `ada/` — **Ada/SPARK root-задача** + валидация bare-metal runtime на AArch64 (см. `ada/README.md`).

## Сборка и запуск (через seL4_tools)
```bash
# 1. Выкачать каркас (repo)
mkdir sel4proj && cd sel4proj
repo init -u https://github.com/seL4/sel4test-manifest.git --depth=1
repo sync -j8

# 2. Положить hello app в projects/sel4test/apps/hello/ (CMakeLists.txt + src/main.c)
#    и в projects/sel4test/CMakeLists.txt заменить:
#      add_subdirectory(apps/sel4test-driver)  ->  add_subdirectory(apps/hello)

# 3. Собрать
mkdir build && cd build
../griddle --PLATFORM=qemu-arm-virt --SIMULATION=ON --KernelSel4Arch=aarch64
ninja

# 4. Запустить
./simulate
```

## Следующие шаги
- **Ada root-задача** — ✅ валидирована: полный цикл elfloader → ядро → Ada root task работает в QEMU (см. `ada/README.md`).
- **virtio-net в QEMU** — ✅ валидированы TX + RX + ICMP echo + DHCP + TCP/HTTP + TCP-сервер + DNS под seL4 (см. `ada/README.md`).
- Рефакторинг драйвера ✅: кольцо дескрипторов (split-ring: RX-пул + ротация TX, рециклинг через used ring) и маршрутизация virtio-IRQ через seL4 Notifications (`IRQControl_Get` → Notification → блокирующий `seL4_Wait` в waiter-треде + Ack).
- Изоляция (increment 2) ✅: драйвер IRQ-пути + протокол выполняются в child-домене со своим CSpace (self CNode + RAM untyped + IRQ handler + VSpace + result notification); device (MMIO/DMA/queues) инициализирует root-задача, VSpace пока общий.
- Драйвер Ethernet **GENET** (Pi 4) — вместо e1000e.
