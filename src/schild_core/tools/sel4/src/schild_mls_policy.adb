-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

package body Schild_MLS_Policy
  with SPARK_Mode => On
is

   -- ─── No Read Up ───
   function Can_Read
     (Subject : Clearance;
      Object  : Clearance) return Boolean
   is
   begin
      return Subject >= Object;
   end Can_Read;

   -- ─── No Write Down ───
   function Can_Write
     (Subject : Clearance;
      Object  : Clearance) return Boolean
   is
   begin
      return Subject <= Object;
   end Can_Write;

   -- ─── Strict IPC ───
   function Can_IPC
     (Sender   : Clearance;
      Receiver : Clearance) return Boolean
   is
   begin
      return Sender = Receiver;
   end Can_IPC;

   -- ─── Check send permission ───
   function Check_Send
     (Sender_Clearance   : Clearance;
      Receiver_Clearance : Clearance) return Access_Result
   is
   begin
      if Can_IPC (Sender_Clearance, Receiver_Clearance) then
         return Allowed;
      elsif Sender_Clearance < Receiver_Clearance then
         return Denied_No_Write_Down;  -- can't write up
      else
         return Denied_No_Read_Up;     -- receiver can't read down
      end if;
   end Check_Send;

   -- ─── Check read permission ───
   function Check_Read
     (Reader_Clearance : Clearance;
      Data_Clearance   : Clearance) return Access_Result
   is
   begin
      if Can_Read (Reader_Clearance, Data_Clearance) then
         return Allowed;
      else
         return Denied_No_Read_Up;
      end if;
   end Check_Read;

   -- ─── Register a process ───
   procedure Register_Process
     (Daemon : in out MLS_Daemon;
      PID    : Process_ID;
      Level  : Clearance)
   is
   begin
      Daemon.Num_Processes := Daemon.Num_Processes + 1;
      Daemon.Processes (Daemon.Num_Processes) :=
        (PID => PID, Level => Level, Active => True);
   end Register_Process;

   -- ─── Look up clearance ───
   function Lookup_Clearance
     (Daemon : MLS_Daemon;
      PID    : Process_ID) return Clearance
   is
   begin
      for I in 1 .. Daemon.Num_Processes loop
         if Daemon.Processes (I).PID = PID then
            return Daemon.Processes (I).Level;
         end if;
      end loop;
      return Public;  -- unknown processes get lowest clearance (fail-closed)
   end Lookup_Clearance;

   -- ─── Authorize IPC between processes ───
   function Authorize_IPC
     (Daemon : MLS_Daemon;
      Msg    : IPC_Message) return Access_Result
   is
      Sender_Level   : Clearance;
      Receiver_Level : Clearance;
   begin
      Sender_Level   := Lookup_Clearance (Daemon, Msg.Sender);
      Receiver_Level := Lookup_Clearance (Daemon, Msg.Receiver);
      return Check_Send (Sender_Level, Receiver_Level);
   end Authorize_IPC;

   -- ─── Initialize ───
   procedure Initialize
     (Daemon : out MLS_Daemon)
   is
   begin
      Daemon.Num_Processes := 0;
      Daemon.Processes := (others => (PID => 0, Level => Public, Active => False));
   end Initialize;

   --  C-level mapping 0..4 -> security level.
   Level_Map : constant array (0 .. 4) of Clearance :=
     (Public, Internal, Confidential, Secret, Top_Secret);

   --  C-callable Bell-LaPadula gate: delegates to the verified Can_Read /
   --  Can_Write / Can_IPC functions. Malformed requests are denied.
   function Mls_Authorize_Op
     (Op           : Unsigned_32;
      Sender_Level : Unsigned_32;
      Target_Level : Unsigned_32) return Unsigned_32
   is
   begin
      if Op > 2 or Sender_Level > 4 or Target_Level > 4 then
         return 0;  --  malformed request -> deny
      end if;
      if Op = 0 then
         return (if Can_Read (Level_Map (Integer (Sender_Level)),
                              Level_Map (Integer (Target_Level))) then 1 else 0);
      elsif Op = 1 then
         return (if Can_Write (Level_Map (Integer (Sender_Level)),
                               Level_Map (Integer (Target_Level))) then 1 else 0);
      else
         return (if Can_IPC (Level_Map (Integer (Sender_Level)),
                             Level_Map (Integer (Target_Level))) then 1 else 0);
      end if;
   end Mls_Authorize_Op;

end Schild_MLS_Policy;
