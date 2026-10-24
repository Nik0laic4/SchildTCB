-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- =============================================================================
-- Schild TCB Stage 7.2 — MLS Policy Daemon (Bell-LaPadula enforcement)
--
-- Enforces mandatory access control with formal SPARK contracts.
-- Inspired by Junos isolated daemon architecture: each security domain
-- runs as an independent server with minimal capability rights.
--
-- Rules (formally verified):
--   1. No Read Up    — process cannot read data above its clearance
--   2. No Write Down — process cannot write data below its clearance
--   3. Strict IPC    — IPC only between equal clearance levels
-- =============================================================================

with Schild_Config_Daemon; use Schild_Config_Daemon;
with Interfaces;          use Interfaces;

package Schild_MLS_Policy
  with SPARK_Mode => On
is
   -- Reuse security levels from Config Daemon
   subtype Clearance is Security_Level;

   -- Process identifier
   type Process_ID is mod 2**16;

   -- IPC message (simplified for embedded kernel)
   type IPC_Message is record
      Sender    : Process_ID;
      Receiver  : Process_ID;
      Data_Size : Unsigned_64;  -- payload size in words
   end record;

   -- Access decision
   type Access_Result is (Allowed, Denied_No_Read_Up, Denied_No_Write_Down);

   -- ─── Core Bell-LaPadula Rules ───

   -- No Read Up: subject can read object only if subject clearance >= object
   function Can_Read
     (Subject : Clearance;
      Object  : Clearance) return Boolean
   with
     Post => Can_Read'Result = (Subject >= Object);

   -- No Write Down: subject can write object only if subject clearance <= object
   function Can_Write
     (Subject : Clearance;
      Object  : Clearance) return Boolean
   with
     Post => Can_Write'Result = (Subject <= Object);

   -- Strict IPC: communication only between equal clearance levels
   function Can_IPC
     (Sender   : Clearance;
      Receiver : Clearance) return Boolean
   with
     Post => Can_IPC'Result = (Sender = Receiver);

   -- ─── Policy decision ───

   -- Check if a process can send a message to another process
   function Check_Send
     (Sender_Clearance   : Clearance;
      Receiver_Clearance : Clearance) return Access_Result
   with
     Post => (if Check_Send'Result = Allowed then
                Sender_Clearance = Receiver_Clearance);

   -- Check if a process can read data at a given clearance
   function Check_Read
     (Reader_Clearance : Clearance;
      Data_Clearance   : Clearance) return Access_Result
   with
     Post => (if Check_Read'Result = Allowed then
                Reader_Clearance >= Data_Clearance);

   -- ─── Process registry ───
   Max_Processes : constant := 32;

   type Process_Entry is record
      PID       : Process_ID;
      Level     : Clearance;
      Active    : Boolean;
   end record;

   type Process_Table is array (1 .. Max_Processes) of Process_Entry;

   type MLS_Daemon is record
      Processes     : Process_Table;
      Num_Processes : Natural range 0 .. Max_Processes;
   end record;

   -- Register a process with its clearance level
   procedure Register_Process
     (Daemon : in out MLS_Daemon;
      PID    : Process_ID;
      Level  : Clearance)
   with
     Pre  => Daemon.Num_Processes < Max_Processes,
     Post => Daemon.Num_Processes = Daemon.Num_Processes'Old + 1;

   -- Look up a process clearance. Unknown PIDs return the lowest clearance
   -- (Public) so an unregistered process is fail-closed: it can neither read
   -- up nor IPC above the Public compartment.
   function Lookup_Clearance
     (Daemon : MLS_Daemon;
      PID    : Process_ID) return Clearance;

   -- Authorize IPC between two processes
   function Authorize_IPC
     (Daemon : MLS_Daemon;
      Msg    : IPC_Message) return Access_Result;

   -- Initialize daemon with empty process table
   procedure Initialize
     (Daemon : out MLS_Daemon)
   with
     Post => Daemon.Num_Processes = 0;

   --  C-callable gate for the seL4 MLS server thread (mls_server.c).
   --  Op: 0 = read, 1 = write, 2 = equal-clearance IPC.
   --  Levels: 0..4 (Public..Top_Secret). Returns 1 = allowed, 0 = denied.
   function Mls_Authorize_Op
     (Op           : Unsigned_32;
      Sender_Level : Unsigned_32;
      Target_Level : Unsigned_32) return Unsigned_32
   with Export, Convention => C, External_Name => "schild_mls_authorize_op";

end Schild_MLS_Policy;
