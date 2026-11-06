-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

with System;

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

   -- Persist the buffered audit trail to SchildFS via the FS daemon (IPC).
   -- Non-destructive text snapshot (index-based read, does not advance Tail).
   -- The snapshot is written into the shared DMA frame and the FS daemon's
   -- Append op writes it to audit.log.  Survives power loss (SchildFS CRC).
   procedure Persist_Audit_Log (Logger : in out Audit_Logger;
                                FS_EP  : Unsigned_64;
                                Persisted : out Boolean) with SPARK_Mode => Off is
      type Byte_Buf is array (Natural range <>) of Unsigned_8;
      Buf : Byte_Buf (0 .. 8191) := (others => 0);
      Pos : Integer := 0;
      N   : Natural := Buffered_Events (Logger);
      Len : Unsigned_32 := 0;

      -- Copy the snapshot into the shared frame @ 0x52A000 (offset 0).
      procedure Shared_Copy_To (Src : System.Address; Len : Unsigned_32);
      pragma Import (C, Shared_Copy_To, "schild_shared_copy_to");

      -- Root-side IPC: Call(fs_ep, op=Append, name_len=0, len) and report
      -- success (reply status == St_Ok).  "audit.log" is the FS daemon's fixed
      -- append target for now (H72 generic-name path deferred).
      function C_FS_Append (FS_EP : Unsigned_64; Name_Len : Unsigned_32; Len : Unsigned_32) return Unsigned_32;
      pragma Import (C, C_FS_Append, "schild_fs_append_ipc");

      procedure Put_Ch (C : Character) is
      begin
         if Pos < Buf'Length then Buf (Pos) := Character'Pos (C); Pos := Pos + 1; end if;
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
      Persisted := False;
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
         -- H72: chunked append. The shared frame is 4 KB, so an 8 KB snapshot
         -- is transferred in up-to-4096-byte chunks, each appended in order.
         declare
            Sent   : Integer := 0;
            Ok_All : Boolean := True;
         begin
            while Sent < Pos loop
               declare
                  Chunk : constant Integer := Integer'Min (4096, Pos - Sent);
               begin
                  Len := Unsigned_32 (Chunk);
                  Shared_Copy_To (Buf (Sent)'Address, Len);
                  if C_FS_Append (FS_EP, 0, Len) /= 1 then
                     Ok_All := False;
                     exit;
                  end if;
                  Sent := Sent + Chunk;
               end;
            end loop;
            Persisted := Ok_All;
         end;
      end if;
   end Persist_Audit_Log;

end Schild_Audit_Logger;
