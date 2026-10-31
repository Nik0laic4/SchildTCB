-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- =============================================================================
-- Schild TCB Stage 7.1 — Config Daemon body (SPARK_Mode => On)
-- =============================================================================

package body Schild_Config_Daemon
  with SPARK_Mode => On
is

   -- Hardware bit-flip detection (XOR EEC): fingerprint over the daemon state.
   -- Validate_Config refuses a state whose checksum no longer matches (a soft
   -- error corrupted a Word/enum field). Defensive, not a security boundary.
   function Compute_State_Checksum (Daemon : Config_Daemon) return Word is
      C : Word := 16#A5A5_5A5A#;
   begin
      C := C xor Word (Daemon_Mode'Pos (Daemon.Mode));
      C := C xor Word (Daemon.Entry_Count);
      C := C xor Daemon.Timeout_Ticks;
      C := C xor Daemon.Audit_Queue;
      for I in Config_State'Range loop
         C := C xor Word (Config_Domain'Pos (Daemon.Current (I).Domain));
         C := C xor Word (Security_Level'Pos (Daemon.Current (I).Min_Level));
         C := C xor Daemon.Current (I).Key;
         C := C xor Daemon.Current (I).Value;
         C := C xor Word (Config_Domain'Pos (Daemon.Pending (I).Domain));
         C := C xor Word (Security_Level'Pos (Daemon.Pending (I).Min_Level));
         C := C xor Daemon.Pending (I).Key;
         C := C xor Daemon.Pending (I).Value;
      end loop;
      return C;
   end Compute_State_Checksum;

   -- Default safe configuration (Bell-LaPadula minimum access)
   Default_Config : constant Config_State :=
     (1  => (Domain   => Domain_Security,
             Key      => 16#A000#,  -- max clearance
             Value    => 5,          -- Top_Secret
             Min_Level => Top_Secret),
      2  => (Domain   => Domain_Security,
             Key      => 16#A001#,  -- audit level
             Value    => 3,          -- Error
             Min_Level => Secret),
      3  => (Domain   => Domain_Network,
             Key      => 16#B000#,  -- firewall enabled
             Value    => 1,          -- ON
             Min_Level => Confidential),
      4  => (Domain   => Domain_Boot,
             Key      => 16#C000#,  -- verify signatures
             Value    => 1,          -- ON
             Min_Level => Top_Secret),
      others => (Domain   => Domain_Security,
                 Key      => 0,
                 Value    => 0,
                 Min_Level => Top_Secret));

   -- ─── SPARK-verified validation ───
   function Validate_Config
     (Daemon : Config_Daemon;
      Level  : Security_Level) return Boolean
   is
   begin
      -- Refuse a state whose checksum no longer matches (hardware bit-flip).
      if Daemon.State_Checksum /= Compute_State_Checksum (Daemon) then
         return False;
      end if;
      -- Every entry must be accessible at the caller's clearance level
      for I in 1 .. Daemon.Entry_Count loop
         if Daemon.Pending (I).Min_Level > Level then
            return False;
         end if;
      end loop;
      return True;
   end Validate_Config;

   -- ─── Initialize daemon ───
   procedure Initialize
     (Daemon : out Config_Daemon)
   is
   begin
      Daemon.State_Checksum := 0;  -- ensure OUT field is set before the recompute
      Daemon.Mode          := Idle;
      Daemon.Current       := Default_Config;
      Daemon.Pending       := Default_Config;
      Daemon.Entry_Count   := 4;  -- default entries
      Daemon.Timeout_Ticks := 0;
      Daemon.Audit_Queue   := 0;
      Daemon.State_Checksum := Compute_State_Checksum (Daemon);
   end Initialize;

   -- ─── Apply tentative configuration ───
   procedure Apply_Tentative
     (Daemon : in out Config_Daemon;
      Timeout : Word)
   is
   begin
      Daemon.Mode          := Tentative;
      Daemon.Timeout_Ticks := Timeout;
      Daemon.Audit_Queue   := Daemon.Audit_Queue + 1;
      Daemon.State_Checksum := Compute_State_Checksum (Daemon);
   end Apply_Tentative;

   -- ─── Commit (make permanent) ───
   procedure Commit
     (Daemon : in out Config_Daemon)
   is
   begin
      Daemon.Current     := Daemon.Pending;
      Daemon.Mode        := Committed;
      Daemon.Timeout_Ticks := 0;
      Daemon.Audit_Queue := Daemon.Audit_Queue + 1;
      Daemon.State_Checksum := Compute_State_Checksum (Daemon);
   end Commit;

   -- ─── Rollback (revert to saved state) ───
   procedure Rollback
     (Daemon : in out Config_Daemon)
   is
   begin
      Daemon.Pending       := Daemon.Current;
      Daemon.Mode          := Idle;
      Daemon.Timeout_Ticks := 0;
      Daemon.Audit_Queue   := Daemon.Audit_Queue + 1;
      Daemon.State_Checksum := Compute_State_Checksum (Daemon);
   end Rollback;

   -- ─── Tick — decrement timeout, auto-rollback on expiry ───
   procedure Tick
     (Daemon : in out Config_Daemon)
   is
   begin
      if Daemon.Mode = Tentative then
         if Daemon.Timeout_Ticks > 0 then
            Daemon.Timeout_Ticks := Daemon.Timeout_Ticks - 1;
            Daemon.State_Checksum := Compute_State_Checksum (Daemon);
         else
            -- Timeout expired — auto-rollback (Junos "commit confirmed")
            Rollback (Daemon);
         end if;
      end if;
   end Tick;

   --  C-level mapping 0..4 -> security level.
   Level_Map : constant array (0 .. 4) of Security_Level :=
     (Public, Internal, Confidential, Secret, Top_Secret);

   --  C-callable gate: delegates validation to the verified Validate_Config
   --  contract on the (richer) private default configuration. Malformed
   --  requests are denied; commit/rollback are accepted no-ops.
   function Config_Authorize_Op
     (Op    : Unsigned_32;
      Level : Unsigned_32) return Unsigned_32
   is
      State : Config_Daemon;
   begin
      if Op > 2 or Level > 4 then
         return 0;  --  malformed request -> deny
      end if;
      Initialize (State);
      if Op = 0 then
         State.Mode := Validating;
         State.State_Checksum := Compute_State_Checksum (State);
         return (if Validate_Config (State, Level_Map (Integer (Level))) then 1 else 0);
      else
         return 1;  --  commit/rollback accepted (no-op in the gate)
      end if;
   end Config_Authorize_Op;

end Schild_Config_Daemon;
