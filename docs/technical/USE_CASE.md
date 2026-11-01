# Schild TCB — Use case: защищённый сетевой шлюз с MLS

> Конкретный пилотный сценарий, на котором проверяются заявления проекта
> (per-component, без агрегатных «high-assurance»). Каждый пункт трассируется в
> модуль и в механическую проверку. Статус: **пилот / целевое описание** — не все
> шаги ещё валидированы на железе; отмечено явно.

## 1. Цель

Развернуть Schild TCB как **сетевой шлюз с мандатным управлением доступом**
(MLS Bell-LaPadula) между тремя зонами сети: **WAN** (интернет, уровень Public),
**LAN** (рабочая сеть, Internal/Confidential) и **DMZ** (публикуемые сервисы).
Шлюз должен гарантировать, что трафик из менее привилегированной зоны **не может
читать вверх и писать вниз** по уровням секретности — это свойство доказывается
формально, а не декларируется.

## 2. Топология

```
        WAN (Public)                      DMZ (Public..Confidential)       LAN (Internal..Secret)
   ──────────────────┐                 ┌──────────────────────────────┐  ┌────────────────────
   internet ──► [ NetServer: e1000e ] ─►  Static_Server (Public)      │  │  HTTP_Gateway (Internal)
                     │                 │  Net_Firewall (Confidential) │  │  DB_Proxy (Confidential)
                     └─────────┬───────┴──────────────────────────────┘  │  Crypto_Engine (Secret)
                               │                                          └────────────────────
                     Schild TCB root task (Top_Secret) — MLS policy, capability model
```

Один физический интерфейс (e1000e/I219-V) или два — логическая сегментация по
уровням MLS, не по портам. Уровни и роли — из `schild_server_security_policy`
(`02_security`).

## 3. Требования (пилот)

| ID | Требование | Проверка |
|----|-----------|----------|
| UC-1 | Запрос из WAN (Public) может достичь только `Static_Server` (Public) и не выше | `Can_Read`/`Can_Write` в `schild_server_security_policy` (SPARK L4) + QEMU-маркер |
| UC-2 | `HTTP_Gateway` (Internal) не может записать в `Net_Firewall` (Confidential) — no write down | `Can_Write` Post (L4) |
| UC-3 | `Crypto_Engine` (Secret) читает ключевой материал только у равного/выше уровня | `Can_Read` Post (L4) |
| UC-4 | Порты из blocklist (`schild_firewall`) дропаются до диспетчеризации | `schild_firewall` (7 подпрограмм, L4) + QEMU |
| UC-5 | Пакет, который роняет драйвер, не доходит до ядра (containment) | `[CONTAINMENT] core alive after fault` (QEMU) |
| UC-6 | Парсеры ARP/IPv4/ICMP/UDP/TCP не читают за границей буфера | `prove_kernel.sh` → `not-proved: 0` (T1) |

## 4. Конфигурация (пилот)

Уровни (5, Bell-LaPadula): `Public < Internal < Confidential < Secret < Top_Secret`.

| Компонент | Роль (`Server_Role`) | Уровень |
|---|---|---|
| Root task / Audit logger | `Role_Root_Task` / `Role_Audit_Logger` | Top_Secret |
| Crypto engine / KDF | `Role_Crypto_Engine` / `Role_KDF_Service` | Secret |
| DB engine | `Role_DB_Engine` | Secret |
| Firewall / Net filter / TLS / DB proxy | `Role_Net_Firewall` / `Role_Net_Filter` / `Role_TLS_Terminator` / `Role_DB_Proxy` | Confidential |
| HTTP gateway / Media / User worker | `Role_HTTP_Gateway` / `Role_Media_Server` / `Role_User_Worker` | Internal |
| Static server | `Role_Static_Server` | Public |

Правила (доказаны): связь только на одном уровне (`Can_Communicate`), чтение — только
доминирование читателя (`Can_Read`), запись — только доминирование цели (`Can_Write`).

Firewall: blocklist портов + лимитер (`schild_firewall`, `schild_net_limiter`).

## 5. Tier-разбиение (что чем закрыто)

| Tier | Компоненты | Claim | Механизм |
|------|-----------|-------|----------|
| **A** | MLS policy, capability model, process table, firewall verdicts | формально доказано | `prove_kernel.sh` / `verify.sh` (0 unproved VCs) |
| **B** | e1000e, NVMe, сетевой стек | скомпрометированная периферия не доходит до A | containment (NetServer в Ring 3) |
| **C** | packet-filter crypto, полные правила firewall | явно помечено «scaffold», не заявлено | комментарий + `ROADMAP.md` |

**Честное ограничение:** DMA-изоляции нет (нет IOMMU на целевой T580-конфигурации,
на Pi 4 нет SMMU) — см. `THREAT_MODEL.md` §8. Поэтому «изоляция периферии» здесь —
процессная, не шинная.

## 6. Карта угроз (что закрывает пилот)

- **T1** (P1 парсит стек): парсеры L4-доказаны; драйвер/C-шимс — containment.
- **T3** (P1/P2 MLS-bypass): `schild_mls_policy` + `schild_server_security_policy` + `schild_process_manager`.
- **T4** (uninit/overflow/OOB в ядре): `prove_kernel.sh` → `not-proved: 0`.
- **T8** (P1 эксплойт C-шимсов): containment — единственный backstop.

## 7. Критерий приёмки

1. `bash scripts/prove_kernel.sh` → `not-proved: 0`; `bash scripts/verify.sh` → passed.
2. QEMU: `run_tests.sh` — 20 (seL4) / 6 (standalone) маркеров.
3. Ручная демонстрация UC-1/UC-4: запрос с WAN к `Static_Server` проходит; к
   `HTTP_Gateway` — отклоняется (no read up).

## 8. Что ещё не валидировано (не входит в пилот)

- GENET-драйвер на Pi 4 (заблокирован отсутствием железа), DMA-изоляция, signed boot.
