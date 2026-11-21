# R23 — MLS per-file levels + operation-aware gate (дизайн)

> Статус: **дизайн** (перед кодом). Реализация — escalation (Tier A MLS policy + новый IPC-контракт).

## 1. Проблема (THREAT_MODEL §H107/H88, residual R23)

Текущий гейт `Authorize_IPC_Levels` — **коммуникационного уровня**: строгое equal-clearance
(`Can_IPC`). Он не различает файлы и операции:

- **(a)** любой не-root **Top_Secret**-пир (например `Audit_Logger`) может `Fs_Delete("audit.log")`
  — уровни равны, гейт пропускает;
- **(b)** домен ниже уровнем не может даже `Fs_Is_Mounted` — гейт режет всё ниже Top_Secret.

Для одноуровневого прототипа это безопасно (FS-EP cap держит только root, role=0 bypass). Для
мульти-уровневой системы нужны **per-file уровни** + **operation-aware гейт**.

## 2. Классификация операций FS

| Класс | Операции | Правило |
|---|---|---|
| **read** | `Fs_Open` (read), `Fs_Read`, `Fs_Get_Entry` | `Can_Read` — subject ≥ file_level (no read up) |
| **write** | `Fs_Write`, `Fs_Create`, `Fs_Append`, `Fs_Delete` | `Can_Write` — subject ≤ file_level (no write down) |
| **mount-control** | `Fs_Is_Mounted`, `Fs_Is_Read_Only` | любой аутентифицированный (не per-file; закрывает gap b) |
| **init** | `Fs_Init` | только root (role=0) |

## 3. Предлагаемый дизайн

### 3.1. Per-file уровень
- В `Dir_Entry` (schild_fs_core) добавить поле `Level : Security_Level`.
- `Fs_Create` принимает уровень файла (явный параметр; default `Public`).
- `audit.log` создаётся как `Top_Secret`; пользовательские файлы — уровень создателя.

### 3.2. Operation-aware gate (Tier A, SPARK)
В `schild_mls_policy` добавить чистый предикат (по образцу `Authorize_IPC_Levels`):

```ada
function Authorize_File_Op
  (Op           : File_Op_Class;      -- Read / Write / Mount_Control
   Subject_Level : Security_Level;
   File_Level    : Security_Level) return Boolean
with Post => Authorize_File_Op'Result =
  (case Op is
     when Read         => Can_Read  (Subject_Level, File_Level),
     when Write        => Can_Write (Subject_Level, File_Level),
     when Mount_Control=> True);
```

### 3.3. Интеграция
- `fs_daemon.c`: dispatch классифицирует op (0..9) в `File_Op_Class` и вызывает Ada-гейт
  **до** обращения к `schild_fs_*` (аналогично текущему MLS-гейту в `fs_daemon_main`).
- `schild_fs_server`: операции read/write получают `Subject_Level` (из badge) + `File_Level`
  (из `Dir_Entry`) и возвращают `SCHILD_EMLSDENIED` при отказе.

## 4. Затронутые файлы (все Tier A / escalation)

| Файл | Что |
|---|---|
| `schild_mls_policy.ads/.adb` | `Authorize_File_Op` + `File_Op_Class` (escalation §4 #9) |
| `schild_fs_core.ads/.adb` | `Dir_Entry.Level` + парсинг (escalation §4 #4 `Schild_Schild_Fs`) |
| `schild_fs_server.ads/.adb` | гейт в операциях (Tier A allowlist) |
| `fs_daemon.c` / `config_daemon.c` | классификация op → gate (Tier B/C) |
| `THREAT_MODEL` / `ASSURANCE` | закрыть R23 (claims — человек) |

## 5. Открытые вопросы (для решения человеком)

1. **Уровень файла:** явный параметр при `Fs_Create` (рекомендую) или наследование от
   создателя?
2. **Delete:** `Can_Write` (subject ≤ file_level) или отдельное более строгое правило
   «только владелец» (не в BL)?
3. **Mount-control для не-root:** подтвердить, что `Fs_Is_Mounted`/`Fs_Is_Read_Only`
   разрешены любому аутентифицированному (закрывает gap b).
4. **Backward-compat:** `Fs_Open` без указания read/write-намерения — нужен ли флаг
   `Read_Intent`/`Write_Intent`, или уровень операции определяется её типом?

## 6. Порядок реализации (после одобрения дизайна)

1. `schild_mls_policy`: `Authorize_File_Op` + `File_Op_Class` (SPARK, prove).
2. `schild_fs_core`: `Dir_Entry.Level` + версия layout (миграция NVFS версии).
3. `schild_fs_server`: гейт + `SCHILD_EMLSDENIED`.
4. `fs_daemon.c`: op → класс → гейт.
5. `run_tests.sh`: маркеры R23 (мульти-уровневые сценарии).
6. Docs (THREAT_MODEL/ASSURANCE/CHANGELOG) — человек.

## 7. Зависимости и риски

- **Layout NVFS:** добавление поля в `Dir_Entry` меняет on-disk layout → bump `NVFS_Version`
  + авто-переформат (см. H60/H75-путь). Риск потери совместимости с существующими образами.
- **H87 size-sensitivity:** изменение FS-сервера сдвигает раскладку ELF (см. грабли M20) —
  не добавлять root_task-only символы в общие `.c`, проверять `run_tests` после каждого шага.
- **Производительность:** per-op gate — один чистый предикат, накладные расходы минимальны.
