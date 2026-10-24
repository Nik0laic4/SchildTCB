# ARM64 (Raspberry Pi 4B) — порт

## Статус
✅ Полный цикл seL4 AArch64 работает в QEMU: **elfloader → ядро → root task → вывод по UART** (`Hello, Schild TCB (ARM64 root task)!`).

## Структура
- `apps/hello/` — минимальная C root-задача (печать через `seL4_DebugPutChar`, syscall -9).
- `src/` — ранние эксперименты (start.S + debug_io.c, прямая линковка — **не работает без elfloader**, оставлено как история).

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
- Драйвер Ethernet **GENET** (Pi 4) — вместо e1000e.
- Порт **Ada root-задачи** (нужен bare-metal runtime для AArch64).
- Сеть в QEMU (virtio-net) до покупки Pi 4B.
