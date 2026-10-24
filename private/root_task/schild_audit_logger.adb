-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

with Schild_Schild_Fs;

package body Schild_Audit_Logger
  with SPARK_Mode => On
is

   -- ─── Severity check ───
   function Is_Active (Logger : Audit_Logger; Severity : Audit_Level) return Boolean
   is
   begin
      return Severity <= Logger.Min_Severity;
   end Is_Active;

   -- ─── Log an event ───
   procedure Log_Event
     (Logger   : in out Audit_Logger;
      Severity : Audit_Level;
      Domain   : Config_Domain;
      Detail   : Unsigned_64;
      Accepted : out Boolean)
   is
   begin
      Logger.Event_Count := Logger.Event_Count + 1;

      -- Severity filter
      if not Is_Active (Logger, Severity) then
         Accepted := False;
         return;
      end if;

      -- Write event
      Logger.Buffer (Logger.Head) :=
        (Timestamp => Logger.Event_Count,
         Severity  => Severity,
         Domain    => Domain,
         Event_ID  => Logger.Event_Count,
         Detail    => Detail);

      -- Advance head pointer
      if Logger.Head = Buffer_Size - 1 then
         Logger.Head := 0;
      else
         Logger.Head := Logger.Head + 1;
      end if;

      -- Overflow detection
      if Logger.Head = Logger.Tail then
         Logger.Overflows := Logger.Overflows + 1;
         -- Advance tail (drop oldest event)
         if Logger.Tail = Buffer_Size - 1 then
            Logger.Tail := 0;
         else
            Logger.Tail := Logger.Tail + 1;
         end if;
      end if;

      Accepted := True;
   end Log_Event;

   -- ─── Count buffered events ───
   function Buffered_Events (Logger : Audit_Logger) return Natural
   is
   begin
      if Logger.Head >= Logger.Tail then
         return Logger.Head - Logger.Tail;
      else
         return Buffer_Size - Logger.Tail + Logger.Head;
      end if;
   end Buffered_Events;

   -- ─── Read oldest event ───
   procedure Read_Event
     (Logger : in out Audit_Logger;
      Event  : out Audit_Event)
   is
   begin
      Event := Logger.Buffer (Logger.Tail);
      -- Advance tail pointer
      if Logger.Tail = Buffer_Size - 1 then
         Logger.Tail := 0;
      else
         Logger.Tail := Logger.Tail + 1;
      end if;
   end Read_Event;

   -- ─── Initialize ───
   procedure Initialize
     (Logger       : out Audit_Logger;
      Min_Severity : Audit_Level)
   is
   begin
      Logger.Buffer       := (others => (Timestamp => 0, Severity => Emergency,
                                         Domain => Domain_Security,
                                         Event_ID => 0, Detail => 0));
      Logger.Head         := 0;
      Logger.Tail         := 0;
      Logger.Event_Count  := 0;
      Logger.Overflows    := 0;
      Logger.Min_Severity := Min_Severity;
   end Initialize;

   -- Persist the buffered audit trail to SchildFS ("audit.log"). Non-destructive
   -- text snapshot (index-based read, does not advance Tail) so the live ring
   -- stays intact for /debug. Survives a power loss thanks to SchildFS CRC.
   procedure Persist_Audit_Log (Logger : in out Audit_Logger) with SPARK_Mode => Off is
      use Schild_Schild_Fs;
      Buf : Unsigned_8_Array (0 .. 1023) := (others => 0);
      Pos : Integer := 0;
      F   : File_Info;
      S   : Boolean;
      N   : Natural := Buffered_Events (Logger);

      procedure Put_Ch (C : Character) is
      begin
         if Pos < 1024 then Buf (Pos) := Character'Pos (C); Pos := Pos + 1; end if;
      end Put_Ch;
      procedure Put_S (Str : String) is
      begin
         for I in Str'Range loop Put_Ch (Str (I)); end loop;
      end Put_S;
      procedure Put_U64 (V : Unsigned_64) is
         Tmp : array (0 .. 19) of Unsigned_8;
         TP  : Integer := 19;
         Val : Unsigned_64 := V;
      begin
         if Val = 0 then Tmp (19) := 48; TP := 19;
         else
            while Val > 0 loop
               Tmp (TP) := 48 + Unsigned_8 (Val rem 10);
               TP := TP - 1; Val := Val / 10;
            end loop;
         end if;
         for J in TP + 1 .. 19 loop Put_Ch (Character'Val (Tmp (J))); end loop;
      end Put_U64;
   begin
      if not Is_Mounted then
         Init (S);
         if not S then return; end if;
      end if;
      Open ("audit.log", F, S);
      if not S then
         Create_File ("audit.log", 1024, S);
         if not S then return; end if;
         Open ("audit.log", F, S);
         if not S then return; end if;
      end if;
      Put_S ("audit: total="); Put_U64 (Logger.Event_Count);
      Put_S (" buffered="); Put_U64 (Unsigned_64 (N));
      Put_S (" overflows="); Put_U64 (Logger.Overflows);
      Put_Ch (ASCII.LF);
      for I in 0 .. N - 1 loop
         declare
            Ev  : Audit_Event;
            Idx : constant Natural := (Logger.Tail + I) mod Buffer_Size;
         begin
            Ev := Logger.Buffer (Idx);
            Put_S ("  ev="); Put_U64 (Ev.Event_ID);
            Put_S (" ts="); Put_U64 (Ev.Timestamp);
            Put_S (" sev="); Put_U64 (Unsigned_64 (Audit_Level'Pos (Ev.Severity)));
            Put_S (" dom="); Put_U64 (Unsigned_64 (Config_Domain'Pos (Ev.Domain)));
            Put_S (" detail="); Put_U64 (Ev.Detail);
            Put_Ch (ASCII.LF);
         end;
      end loop;
      if Pos > 0 then
         Write_File (F, Buf (0 .. Pos - 1), S);
      end if;
   end Persist_Audit_Log;

end Schild_Audit_Logger;
