# Schild TCB — Security model

> **Обновлено 2026-08-17:** статусные маркеры приведены в соответствие с текущим кодом;
> каноничные утверждения — в [`ASSURANCE.md`](ASSURANCE.md).

## 🔒 Security audit (2026-08-11) — all 12 vulnerabilities fixed

| ID | Status | Category | Description |
|----|--------|-----------|----------|
| C1 | ✅ | Crit. | One untyped for 2 objects → 4 separate caps |
| C2 | ✅ | Crit. | `$-1` instead of `$-3` for IPC → `schild_sel4_send_ipc` |
| C3 | ⚠️ | Crit. | MLS thread fault handler → Notification 199 (non-MCS seL4 needs endpoint — latent defect) |
| H1 | ✅ | High | MR from registers → read from IPC buffer |
| H2 | ✅ | High | Spurious error checks → removed |
| H3 | ✅ | High | .bss collision → flag before stack |
| H4 | ✅ | Med. | Duplicate BI_Access → removed |
| B1 | ✅ | Med. | endpoint=0 → guard + 0xFF marker |
| B2 | ✅ | Med. | Shift_Left overflow → guard < 64 |
| B3 | ✅ | Med. | R11 convention → documented |
| B5 | ✅ | Med. | rt_panic without output → `!` in UART |
| S1 | ✅ | Info | No TCBWriteRegisters → implemented |

## MLS Policy Daemon (Stage 7.2 — SPARK_Mode => On)

Formal verification of Bell-LaPadula in a dedicated SPARK package:
- `Schild_MLS_Policy`: 4 rules with postconditions
- `Schild_Audit_Logger`: ring buffer with severity filter
- 4 new tests (T5-T8) — all pass in QEMU

## Stage 7.3: CSpace Corruption (TCBSetSpace)

**Vulnerability found:** `TCBSetSpace` (label=10) creates a
derived CNode cap with a CNodePtr in **user-space**
(0x7FC00FFD0000) instead of kernel-space (0xFFFFFF80...).

Any subsequent `lookupCapAndSlot` → General Protection Fault.
**Solution:** avoid TCBSetSpace; use direct extra caps.

## MLS (Mandatory Labeling Security)

Bell-LaPadula model with formal SPARK contracts.

### Security levels

| Level | Index | Example processes |
|---------|--------|-------------------|
| **Public** | 1 | Static server, public APIs |
| **Internal** | 2 | HTTP gateway, media server |
| **Confidential** | 3 | Firewall, TLS terminator, DB proxy |
| **Secret** | 4 | Crypto engine, KDF service |
| **Top_Secret** | 5 | Root Task, Audit logger |

### Rules (formally proven)

| Rule | SPARK | Description |
|---------|-------|----------|
| **No Read Up** | ✅ Level 4 | A process reads only ≤ its level |
| **No Write Down** | ✅ Level 4 | A process writes only ≥ its level |
| **Strict IPC** | ✅ Level 4 | IPC only between equal levels |
| **No Control Up** | ✅ QEMU | Only a higher/equal level may terminate |

### Server roles (14)

```
Root_Task(5) → Init_Manager(4) → Crypto_Engine(4) → KDF_Service(4)
                                 → Audit_Logger(5)
                                 → Net_Firewall(3) → Net_Filter(3)
                                 → TLS_Terminator(3)
                                 → HTTP_Gateway(2) → Media_Server(2)
                                 → User_Worker(2)
                                 → DB_Proxy(3) → DB_Engine(4)
                                 → Static_Server(1)
```

## SPARK verification

| Module | Level | Result |
|--------|-------|--------|
| Schild_Mls_Policy | Level 4 | Bell-LaPadula: 11/11 subprograms, 0 unproved |
| Schild_Config_Daemon | Level 4 | Validate_Config/Commit/Rollback — proved |
| Schild_Audit_Logger | Level 4 | Initialize/Log_Event/Read_Event — proved |
| Schild_Boot_Manager | Level 4 | A/B Failover/Verify_Image — proved |

Only these four units are in the `verify.gpr` proof set (run by `scripts/verify.sh`);
every other module is either `SPARK_Mode => Off` (HW/driver/crypto) or flow-analyzed only.

## Vulnerability audit

| CVE | Date | Vulnerabilities | Status |
|-----|------|-------------|--------|
| [CVE-2026-SCHILD-01](security/CVE-2026-SCHILD-01.md) | 2026-08-09 | 8 | ✅ Fixed |
| [CVE-2026-SCHILD-02](security/CVE-2026-SCHILD-02.md) | 2026-08-09 | 5 | ✅ Fixed |

## Distributed ledger subsystem (disablable module)

| Role | MLS level |
|------|-------------|
| Key_Storage | Top_Secret |
| Consensus Engine | Secret |
| VM Runtime (TBM) | Confidential |
| Network Adapter | Internal |
| API Gateway | Public |

## Audit v0.5.0-pre (session 2026-08-09)

### QEMU tests
```
[E1000E] Scanning PCI...
[PCI] Device found
[E1000E] Device found, MMIO mapped
[E1000E] Ring addr programmed
[E1000E] Init OK
[E1000E] TX test frame sent
[INTR] IDT loaded, interrupts initialized
[AUDIT] Test1 Root: PASS
[AUDIT] Test2 SameLevel: PASS
[AUDIT] Test3 CrossLevel: PASS
[AUDIT] Test4 Terminate: PASS
[AUDIT] Test4 Reap: PASS
[AUDIT] Test5 MLS Terminate: PASS
[LOGIC] Preemptive scheduler ready (PIT 100Hz)
[LOGIC] Entering kernel loop (busy-wait)...
```

### Security status
- ✅ MLS Bell-LaPadula: 8/8 tests
- ✅ SPARK Level 4 (verify.gpr): MLS policy + 3 daemons, 0 unproved
- ✅ CVE-2026-SCHILD-01: 8 fixed
- ✅ CVE-2026-SCHILD-02: 5 fixed
- ✅ Scheduler: honest PIT timer (100 Hz, IRQ0) + sti/hlt idle (no busy-wait)
