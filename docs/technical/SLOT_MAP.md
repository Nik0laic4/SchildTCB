# Schild TCB — CSpace Slot Map (единая таблица слотов)

**Версия:** v0.1 | **Дата:** 2026-11-15
**Источник истины для ручной сверки:** константы в `schild_sel4_syscall.ads`
(`Slot_Base = 4096` + смещение). Авто-проверка дублей — `scripts/check_slot_layout.sh`.

## 1. Даемон-окна (image + mint + shared + PML4)

| Даемон | Image_Base | Кадры | Mint (offset) | Mint окно | Shared | PML4/PDPT/PD/PT |
|---|---|---|---|---|---|---|
| MLS | +55 (4151) | 9 | +64 | 4215..4223 | +84 | +85..+88 |
| Config | +300 (4396) | 9 | +64 | 4460..4468 | +310/+311 | +312..+315 |
| NetServer | +316 (4412) | 40 | **+3200** | 7612..7651 | +356/+357 | (Net_PML4 +10) |
| FS | +384 (4480) | 42 | +64 | 4544..4585 | +76 | +71..+74 |

## 2. Системные окна

| Окно | Диапазон | Назначение |
|---|---|---|
| Root image (User_Image_Frames) | 0..~4430 (динамика: ~207 кадров) | корневой образ root_task.elf |
| MMIO (e1000e + NVMe BAR0) | 4608..~7455 (Offset_Frames+32) | PCI-окно, device-untyped |
| FS_Nvme_Frame_Base | +1024 (5120, fallback) | резерв (перекрыт MMIO-окном) |
| Image_Frame_Base | +128 (4224) | **мёртвая константа** (NetServer больше не минтит образ — Load_Elf, v0.51) |
| **Bootstrap (H87-L, v0.53)** | 7652..7667 | PML4/PDPT/PD/PT_Lo/PT_Hi/TCB/SC/Reply/IPC/Fault_EP/PT_Hi2/BootInfo×2 + copy slots |
| Bootstrap Image_Frame_Base | +3567 (7663→7667 после расширения) | образ root task (~1087 кадров) + mint offset 1200 |

## 3. Примечания

- **Правило mint**: `mint_слот = Image_Frame_Base + mint_offset`; mint должен попадать в
  свободное окно (не в root image, не в MMIO, не в другой даемон).
- NetServer — единственный с большим mint-offset (3200), т.к. его 40-кадровый mint
  не влезал в низкое окно (коллизии «Slot #N non-empty»: `+90→+55`, Config `+259→+300`).
- `Image_Frame_Base` (+128) — остаток от старого mint-цикла NetServer'а, не используется
  после v0.51 (оставлена как историческая константа, не удалять без ревизии).
- При добавлении нового даемона: выбери Image_Base + mint так, чтобы окна не пересекались;
  прогони `check_slot_layout.sh` + run_tests.
