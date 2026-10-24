# private — полные реализации демонов Schild TCB (оверлей SCHILD_PROFILE=private)

В этой папке находятся полные реализации демонов, которые подключаются к
сборке только при включённом профиле `SCHILD_PROFILE=private` (тумблер
вкл/выкл в `tools/sel4/build_rt.sh`). В базовом профиле
(`SCHILD_PROFILE=public`) вместо них компилируются заглушки (stub), лежащие
в `src/` проекта.

## Состав

```
root_task/
  schild_audit_logger.adb/.ads     Журнал аудита (кольцевой буфер, гарантированная доставка)
  schild_config_daemon.adb/.ads    Конфигурационный демон (транзакционный commit-confirmed)
  schild_boot_manager.adb/.ads     A/B-загрузчик (failover с проверкой SHA-256)
  schild_net_runtime.c             Рантайм NetServer (реальный Schild_Debug_Render)
```

## Сборка (тумблер SCHILD_PROFILE)

```bash
# Базовая сборка — stub-модули
SCHILD_PROFILE=public  bash tools/sel4/build_rt.sh

# Полная сборка — оверлей реальных модулей из private/root_task/
SCHILD_PROFILE=private bash tools/sel4/build_rt.sh
```

При `SCHILD_PROFILE=private` скрипт `tools/sel4/build_rt.sh` копирует реальные
`.adb`-тела из этой папки поверх заглушек (оверлей seL4 root-задачи).
