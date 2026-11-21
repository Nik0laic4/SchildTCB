# R23 — MLS per-file levels + operation-aware gate (дизайн)

> Статус: **дизайн одобрен**; реализация — escalation (Tier A MLS policy + Schild_Schild_Fs).

## 1. Проблема (THREAT_MODEL §H107/H88, residual R23)

Текущий гейт `Authorize_IPC_Levels` — **коммуникационного уровня** (equal-clearance), не различает
файлы и операции: (a) любой не-root Top_Secret-пир может `Fs_Delete("audit.log")`; (b) домен ниже
уровнем не может даже `Fs_Is_Mounted`. Нужны per-file уровни + operation-aware гейт.

## 2. Классификация операций (финальная)

| Класс | Операции | Правило |
|---|---|---|
| **read** | `Fs_Open` (Read), `Fs_Read`, `Fs_Get_Entry` | `Can_Read` — subject ≥ file_level (no read up) |
| **write** | `Fs_Open` (Write), `Fs_Write`, `Fs_Create`, `Fs_Append` | `Can_Write` — subject ≤ file_level (no write down) |
| **delete** | `Fs_Delete` | **owner-only**: `subject_role = 0 (root)` или `subject_role = Owner_Role` |
| **mount-control** | `Fs_Is_Mounted`, `Fs_Is_Read_Only` | любой аутентифицированный (закрывает gap b) |
| **init** | `Fs_Init` | только root (role=0) |

## 3. Дизайн

### 3.1. Per-file метаданные
- `Dir_Entry` (schild_fs_core) + `Level : Security_Level` и `Owner : Owner_Role`.
- `Fs_Create` принимает уровень файла (явный параметр, default `Public`); `Owner` = роль создателя.
- `Fs_Open` принимает `Mode ∈ {Read, Write}` — авторизация на границе (закрывает утечку
  существования файла неавторизованному).

### 3.2. Operation-aware gate (Tier A, SPARK)
```ada
type File_Op_Class is (Read, Write, Delete, Mount_Control);

function Authorize_File_Op
  (Op            : File_Op_Class;
   Subject_Level : Security_Level;
   File_Level    : Security_Level;
   Subject_Role  : Unsigned_32;      -- badge role (0 = root)
   Owner_Role    : Unsigned_32) return Boolean
with Post => Authorize_File_Op'Result =
  (case Op is
     when Read          => Can_Read  (Subject_Level, File_Level),
     when Write         => Can_Write (Subject_Level, File_Level),
     when Delete        => Subject_Role = 0 or Subject_Role = Owner_Role,
     when Mount_Control => True);
```

### 3.3. Интеграция
- `fs_daemon.c`: dispatch классифицирует op в `File_Op_Class`, передаёт badge-role/level и
  вызывает Ada-гейт **до** `schild_fs_*`.
- `schild_fs_server`: `Fs_Open(Mode, …)` гейтится на входе; read/write возвращают
  `SCHILD_EMLSDENIED` при отказе.

## 4. Затронутые файлы (Tier A / escalation)

| Файл | Что |
|---|---|
| `schild_mls_policy.ads/.adb` | `File_Op_Class` + `Authorize_File_Op` (escalation §4 #9) |
| `schild_fs_core.ads/.adb` | `Dir_Entry.Level` + `Dir_Entry.Owner` + парсинг (escalation §4 #4) |
| `schild_fs_server.ads/.adb` | `Fs_Open(Mode)`, owner-only delete, gate (Tier A allowlist) |
| `fs_daemon.c` | op → класс → гейт (Tier B/C) |
| `THREAT_MODEL`/`ASSURANCE`/`CHANGELOG` | закрыть R23 (claims — человек) |

## 5. Решённые вопросы

1. **Уровень файла:** явный параметр при `Fs_Create`.
2. **Delete:** только владелец (`Owner_Role`) или root — закрывает gap (a).
3. **Mount-control:** любой аутентифицированный (закрывает gap b).
4. **Fs_Open:** флаг `Mode ∈ {Read, Write}` (Вариант B).

## 6. Порядок реализации

1. `schild_mls_policy`: `File_Op_Class` + `Authorize_File_Op` (SPARK, prove).
2. `schild_fs_core`: `Dir_Entry.Level` + `Owner` + bump `NVFS_Version`.
3. `schild_fs_server`: `Fs_Open(Mode)`, owner-only delete, gate.
4. `fs_daemon.c`: op → класс → гейт.
5. `run_tests.sh`: маркеры R23.
6. Docs (человек).

## 7. Зависимости и риски

- **Layout NVFS:** добавление полей меняет on-disk layout → bump `NVFS_Version` + авто-переформат (H60/H75).
- **H87 size-sensitivity:** сдвиг раскладки ELF (см. грабли M20) — проверять `run_tests` после каждого шага.
