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
   -- NOTE (intentional level-model divergence): this is a 5-level *military*
   -- scheme. The standalone kernel uses a 4-level *commercial* scheme --
   -- Schild_Mls_Core_Engine.Clear_Level_Type 1..4 = (Public, Restricted,
   -- Confidential, Secret). They run in separate images; level 2 here is
   -- "Internal" (not "Restricted") and this model adds "Top_Secret" on top.
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
      State_Checksum : Word := 0;  -- XOR EEC over the state (bit-flip detection)
   end record;

   -- Recompute the state checksum. A hardware bit-flip in any Word/enum field
   -- changes this fingerprint; Validate_Config refuses a mismatching state.
   function Compute_State_Checksum (Daemon : Config_Daemon) return Word
   with Global => null;

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
     Post => (if Daemon.Mode'Old = Tentative and Daemon.Timeout_Ticks'Old = 0
              then Daemon.Mode = Idle);

   -- Initialize daemon with default (safe) configuration
   procedure Initialize
     (Daemon : out Config_Daemon)
   with
     Post => Daemon.Mode = Idle;

   -- C-callable gate for the Config Daemon thread (config_daemon.c).
   -- Validation delegates to the verified Validate_Config contract on the
   -- scaffold's default configuration; commit/rollback are accepted no-ops.
   -- Op: 0 = validate, 1 = commit, 2 = rollback. Level: 0..4 (Public..Top_Secret).
   -- Returns 1 = allowed, 0 = denied.
   function Config_Authorize_Op
     (Op    : Unsigned_32;
      Level : Unsigned_32) return Unsigned_32
   with Export, Convention => C, External_Name => "schild_config_authorize_op";

end Schild_Config_Daemon;
