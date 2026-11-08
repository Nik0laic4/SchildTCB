# Schild TCB — Guide: seL4 root-task на Ada/SPARK

> Учебник-маршрут «с нуля до собранного, запущенного и формально доказанного
> root-task». Это **порядок действий**, а не справочник: каждый шаг — команда с
> механически проверяемым результатом. Единый источник истины по числам и
> каноничным докам — `docs/README.md`; приёмы доказательства —
> `docs/technical/SPARK_PROOF_TECHNIQUES.md`.

## 0. Что вы строите

Schild TCB — **два артефакта**, их важно не путать:

1. **bare-metal OS** на Ada — загрузчик, NVMe-драйвер, e1000e, TCP/IP, HTTP.
   Работает на ThinkPad T580 и в QEMU. Отвечает на «работает ли?».
2. **seL4 root-task** на Ada/SPARK + демоны — микроядро upstream (формально
   верифицировано), вклад — root-task и демоны; сеть/хранилище изолированы в
   Ring 3. Отвечает на «доказано ли?».

## 1. Предварительные требования

- Linux x86_64; Alire `alr` 2.1.1; `gnat_native` 14.2.1; `gprbuild` 22.0.1;
  `gnatprove` 14.1.1.
- Системные пакеты: `grub-pc-bin grub-common xorriso mtools qemu-system-x86
  python3 make binutils gcc`.
- Быстрый старт без ручной установки — `Dockerfile` (см. §9).

Точные версии и детерминизм — `docs/technical/TOOL_QUALIFICATION.md`.

## 2. Карта репозитория

| Путь | Что |
|---|---|
| `src/schild_core/src/01_hardware` | MMU, APIC/IOAPIC, NVMe, e1000e, SMP, PIT, планировщик |
| `src/schild_core/src/02_security` | MLS Bell-LaPadula, capability model, IPC, firewall, файловые дескрипторы |
| `src/schild_core/src/03_crypto` | AES, SHA-256, HMAC-SHA256, RNG |
| `src/schild_core/src/04_userland` | SchildFS, сокеты, сетевой стек (ARP/IPv4/TCP/HTTP) |
| `src/schild_core/arm64/` | порт AArch64 (virtio-net), см. `ARM64_VIRTIO_NET.md` |
| `src/schild_core/tools/sel4/` | seL4 root-task, демоны, KAT-тесты |
| `src/schild_core/scripts/` | `build.sh`, `verify.sh`, `prove_kernel.sh`, `verify_private.sh`, `run_tests.sh` |
| `docs/technical/` | каноничные доки (см. `docs/README.md`) |

## 3. Шаг 1 — bare-metal сборка

```bash
cd src/schild_core
./build.sh
```

Ожидаемый результат: `Ada: 184 objects, 0 errors` → `schild_os.elf` +
`schild_os.iso`. Сборка воспроизводима (`SOURCE_DATE_EPOCH`, `-fdebug-prefix-map`).

## 4. Шаг 2 — запуск в QEMU

```bash
# базовый boot (MLS-аудит)
qemu-system-x86_64 -cdrom schild_os.iso -nographic -m 512M

# полный тест (NVMe + e1000e + SMP)
qemu-system-x86_64 -cdrom schild_os.iso -nographic -m 512M -smp 2 \
  -netdev user,id=net0 -device e1000e,netdev=net0 \
  -drive file=nvme_disk.img,if=none,id=nvme0 \
  -device nvme,serial=SCHILD0001,drive=nvme0
```

Готовый маршрут: `SKIP_BUILD=1 SEL4_PRIMARY=0 bash scripts/run_tests.sh` (6 маркеров).

## 5. Шаг 3 — seL4 root-task

```bash
cd src/schild_core
KERNEL_MCS=ON scripts/build_sel4_kernel.sh        # ядро seL4 → tools/sel4/kernel.elf
SEL4_PRIMARY=1 ./build.sh                          # root_task.elf + sel4_primary.iso
SKIP_BUILD=1 SEL4_PRIMARY=1 scripts/run_tests.sh  # QEMU, 23 маркера
```

⚠️ При ручной пересборке ядра: `DEBUG_BUILD=ON` не загружается — нужен
`DEBUG_BUILD=OFF` + `CONFIG_PRINTING=1` (см. `BUILD.md`).

## 6. Шаг 4 — формальная верификация (SPARK Level 4)

```bash
cd src/schild_core
bash scripts/verify.sh            # 8 демонов root-задачи (not-proved: 0)
bash scripts/verify_private.sh     # полные (private) тела демонов
bash scripts/prove_kernel.sh       # полный свип 188 модулей (~10 мин)
```

Каноничный гейт — **`not-proved: 0`**. Число proved/skipped недетерминировано
(±несколько из-за `gnatprove -j8`) — не хардкодить; стабилен только гейт.
Классификатор: `scripts/classify_gnatprove.py`.

## 7. Шаг 5 — как писать доказуемые контракты (кратко)

Метод — `THREAT_MODEL.md` §10, приёмы — `SPARK_PROOF_TECHNIQUES.md`:

- `Pre` принимает **все** легитимные входы (anti-strangling); `Post` = **свойство
  безопасности** (не «что-то вернулось»).
- liveness (трафик течёт, tick→partition корректен) — через runtime/KAT, не proof.
- `pragma Assume` = 0; вакуум (`Post => True`) запрещён.
- Паттерны: frame conditions, loop-инвариант «track max», byte-упаковка,
  модульная арифметика вместо битовых свёрток.

Образцы доказанных модулей: `schild_scheduler` (max-priority),
`schild_server_security_policy` (Bell-LaPadula), `schild_aes_cbc_engine` (CBC),
`schild_tcp_handler` (парсер/строитель).

## 8. Архитектура и модель доверия

- **Tier A/B/C** — `docs/technical/ASSURANCE.md`: A = доказанное ядро (MLS,
  capability, process table, firewall verdicts); B = изолированная периферия
  (сеть/NVMe, containment); C = scaffold (явно помечено).
- **Угрозы T1–T9** — `docs/technical/THREAT_MODEL.md` §7; остаточные риски — §8.
- **Пилотный сценарий** «Защищённый сетевой шлюз с MLS» — `docs/technical/USE_CASE.md`.

## 9. Куда дальше

- План работ — `docs/technical/ROADMAP.md`.
- Воспроизводимость одной командой — `Dockerfile`:
  ```bash
  docker build -t schild-tcb .
  docker run --rm -v "$PWD":/repo schild-tcb            # build + verify
  docker run --rm -v "$PWD":/repo schild-tcb prove-full # полный свип
  ```
- Журнал проверенных результатов — `docs/technical/CHANGELOG.md`.
