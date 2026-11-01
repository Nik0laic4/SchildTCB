# Schild TCB v0.1.0 — release notes (pre-release)

> Честный pre-release исследовательского прототипа. Это НЕ сертифицированная
> система; каждое заявление — per-component (см. `docs/technical/ASSURANCE.md`,
> `THREAT_MODEL.md`). Для вставки в поле «Release notes» на GitHub.

## Что это

Исследовательский прототип доверенной вычислительной базы (TCB): формально
верифицируемое ядро (**seL4** микроядро + **Ada/SPARK 2022**) со средой
изолированной периферии. Два артефакта:

- **bare-metal OS** на Ada (загрузчик, NVMe, e1000e, TCP/IP, HTTP) — T580 и QEMU;
- **seL4 root-task** + демоны, сеть/хранилище изолированы в Ring 3.

## Ключевые результаты (проверяемо)

- 185 модулей ядра прогоняются SPARK **Level 4** с **0 unproved VCs**; ~129 proved / ~56 out-of-proof (`SPARK_Mode => Off` драйверы/платформа).
- 8 демонов root-задачи доказаны (`verify.sh`); полные (private) тела — `verify_private.sh`.
- MLS Bell-LaPadula (5 уровней) доказана в `schild_server_security_policy`, `schild_process_manager`, `schild_file_descriptors`.
- Сеть: ARP/IPv4/ICMP/UDP/TCP-парсеры L4-доказаны (W10); CBC-цепочка, max-priority планировщик + ARINC-653 MTF (W11).
- Загрузка на ThinkPad T580 (32 ГБ) и QEMU; ARM64 (Pi 4B) — порт в работе.

## Честные ограничения (остаточные риски, THREAT_MODEL §8)

1. **Нет DMA-изоляции** (IOMMU/VT-d — upstream-экспериментально; на Pi 4 нет SMMU). «Изоляция» — процессная, не шинная.
2. **Непроверенный C-код** (`net_test.c`, `sel4_mmio.c`, `runtime_stubs.c`, …) — memory-unsafe, закрыт только containment'ом.
3. **Контракты доказывают свойство, не полный end-to-end сценарий** (W11 частично закрыл: CBC/планировщик/MLS).
4. **Нет signed boot / HWRoT** — SHA-256 ловит порчу, а не злонамеренную подмену.
5. **x86_64 MCS верифицирован слабее ARM MCS** (upstream).
6. **Патченый seL4** — upstream-proof переносится частично.
7. **PID reuse** (CVE-2026-SCHILD-02 #005) — отмечено, не смягчено.
8. **ARM64** — virtio-net валидирован в QEMU; GENET (Pi 4) блокирован отсутствием железа.

## Воспроизведение

```bash
cd src/schild_core
./build.sh                          # bare-metal (181 объект, 0 ошибок)
bash scripts/verify.sh              # 8 демонов (not-proved: 0)
bash scripts/prove_kernel.sh        # полный свип 185 (~10 мин)
# Docker: docker build -t schild-tcb . && docker run --rm -v "$PWD":/repo schild-tcb
```
