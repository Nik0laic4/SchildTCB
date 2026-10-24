-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- =============================================================================
-- Schild TCB Stage 7.1 — Config Daemon (Junos-inspired transactional config)
--
-- Pattern: "configure private → validate → commit confirmed <timeout>"
--
-- Every configuration change is:
--   1. Validated via SPARK contracts BEFORE application
--   2. Applied tentatively (old state preserved for rollback)
--   3. Committed within a deadline, or auto-reverted
--
-- This guarantees that the system never stays in a broken configuration
-- state — exactly like Junos "commit confirmed 5" with a 5-minute timer.
-- =============================================================================

with Schild_Sel4_BootInfo; use Schild_Sel4_BootInfo;
with Interfaces;          use Interfaces;

package Schild_Config_Daemon
  with SPARK_Mode => On
is
   -- Configuration domains
   type Config_Domain is (Domain_Security, Domain_Network, Domain_Boot);

   -- MLS security levels (Bell-LaPadula)
   type Security_Level is (Public, Internal, Confidential, Secret, Top_Secret);

   -- Audit verbosity (Junos-style syslog levels)
   type Audit_Level is (Emergency, Alert, Critical, Error,
                         Warning, Notice, Info, Debug);

   -- A single configuration entry
   type Config_Entry is record
      Domain   : Config_Domain;
      Key      : Word;       -- hashed parameter name
      Value    : Word;       -- parameter value
      Min_Level : Security_Level; -- minimum clearance to modify
   end record;

   -- Configuration state (max 16 entries for embedded system)
   Max_Entries : constant := 16;
   type Config_State is array (1 .. Max_Entries) of Config_Entry;

   -- The daemon maintains current + pending state
   type Daemon_Mode is (Idle, Validating, Tentative, Committed);

   -- Main daemon state record
   type Config_Daemon is record
      Mode         : Daemon_Mode;
      Current      : Config_State;
      Pending      : Config_State;
      Entry_Count  : Natural range 0 .. Max_Entries;
      Timeout_Ticks : Word;  -- ticks until auto-rollback
      Audit_Queue  : Word;   -- count of pending audit events
   end record;

   -- SPARK-verified validation
   function Validate_Config
     (Daemon : Config_Daemon;
      Level  : Security_Level) return Boolean
   with
     Pre  => Daemon.Mode = Validating,
     Post => (if Validate_Config'Result then
                (for all I in 1 .. Daemon.Entry_Count =>
                   Daemon.Pending (I).Min_Level <= Level));

   -- Apply configuration tentatively (old state saved)
   procedure Apply_Tentative
     (Daemon : in out Config_Daemon;
      Timeout : Word)
   with
     Pre  => Daemon.Mode = Validating,
     Post => Daemon.Mode = Tentative;

   -- Confirm tentative configuration (makes it permanent)
   procedure Commit
     (Daemon : in out Config_Daemon)
   with
     Pre  => Daemon.Mode = Tentative,
     Post => Daemon.Mode = Committed;

   -- Revert to previous configuration
   procedure Rollback
     (Daemon : in out Config_Daemon)
   with
     Pre  => Daemon.Mode = Tentative,
     Post => Daemon.Mode = Idle;

   -- Auto-rollback on timeout expired
   procedure Tick
     (Daemon : in out Config_Daemon)
   with
     Post => (if Daemon.Mode = Tentative and Daemon.Timeout_Ticks = 0
              then Daemon.Mode = Idle);

   -- Initialize daemon with default (safe) configuration
   procedure Initialize
     (Daemon : out Config_Daemon)
   with
     Post => Daemon.Mode = Idle;

end Schild_Config_Daemon;
