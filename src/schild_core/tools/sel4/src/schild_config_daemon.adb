-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- INTERNAL STUB (TCB execution layer).
-- The proprietary Config Daemon implementation has been moved out of this
-- repository into private/. This body only satisfies the public
-- interface (Schild_Config_Daemon.ads) so the open build compiles and links.

package body Schild_Config_Daemon
  with SPARK_Mode => On
is

   -- Hardware bit-flip detection (XOR EEC): fingerprint over the daemon state.
   -- Validate_Config refuses a state whose checksum no longer matches.
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

   function Validate_Config
     (Daemon : Config_Daemon;
      Level  : Security_Level) return Boolean
   is
   begin
      -- Refuse a state whose checksum no longer matches (hardware bit-flip).
      if Daemon.State_Checksum /= Compute_State_Checksum (Daemon) then
         return False;
      end if;
      -- Honour the spec contract: accept only if every pending entry's
      -- minimum clearance is satisfiable by the caller's level.
      for I in 1 .. Daemon.Entry_Count loop
         if Daemon.Pending (I).Min_Level > Level then
            return False;
         end if;
      end loop;
      return True;
   end Validate_Config;

   procedure Initialize (Daemon : out Config_Daemon) is
   begin
      Daemon.State_Checksum := 0;  -- ensure OUT field is set before the recompute
      Daemon.Mode          := Idle;
      Daemon.Timeout_Ticks := 0;
      Daemon.Audit_Queue   := 0;
      -- Public scaffold default configuration (the proprietary body seeds a
      -- richer policy). Entries carry increasing minimum clearance so the
      -- self-tests can exercise rejection below the required level.
      Daemon.Pending       := (others => (Domain_Security, 0, 0, Public));
      Daemon.Pending (1)   := (Domain_Security, 1, 0, Top_Secret);
      Daemon.Pending (2)   := (Domain_Network,  2, 0, Secret);
      Daemon.Pending (3)   := (Domain_Boot,     3, 0, Internal);
      Daemon.Current       := Daemon.Pending;
      Daemon.Entry_Count   := 3;
      Daemon.State_Checksum := Compute_State_Checksum (Daemon);
   end Initialize;

   procedure Apply_Tentative
     (Daemon  : in out Config_Daemon;
      Timeout : Word)
   is
   begin
      Daemon.Mode          := Tentative;
      Daemon.Timeout_Ticks := Timeout;
      Daemon.State_Checksum := Compute_State_Checksum (Daemon);
   end Apply_Tentative;

   procedure Commit (Daemon : in out Config_Daemon) is
   begin
      Daemon.Mode := Committed;
      Daemon.State_Checksum := Compute_State_Checksum (Daemon);
   end Commit;

   procedure Rollback (Daemon : in out Config_Daemon) is
   begin
      Daemon.Mode := Idle;
      Daemon.State_Checksum := Compute_State_Checksum (Daemon);
   end Rollback;

   procedure Tick (Daemon : in out Config_Daemon) is
   begin
      if Daemon.Mode = Tentative and Daemon.Timeout_Ticks > 0 then
         Daemon.Timeout_Ticks := Daemon.Timeout_Ticks - 1;
         Daemon.State_Checksum := Compute_State_Checksum (Daemon);
      elsif Daemon.Mode = Tentative then
         Daemon.Mode := Idle;
         Daemon.State_Checksum := Compute_State_Checksum (Daemon);
      end if;
   end Tick;

   --  C-level mapping 0..4 -> security level.
   Level_Map : constant array (0 .. 4) of Security_Level :=
     (Public, Internal, Confidential, Secret, Top_Secret);

   --  C-callable gate: delegates validation to the verified Validate_Config
   --  contract. Malformed requests are denied.
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
         return 1;  --  commit/rollback accepted (public scaffold no-op)
      end if;
   end Config_Authorize_Op;

end Schild_Config_Daemon;
