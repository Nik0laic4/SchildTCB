-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- INTERNAL STUB (TCB execution layer).
-- The proprietary Audit Logger implementation has been moved out of this
-- repository into private/. This body only satisfies the public
-- interface (Schild_Audit_Logger.ads) so the open build compiles and links.

package body Schild_Audit_Logger
  with SPARK_Mode => On
is
   function Is_Active (Logger : Audit_Logger; Severity : Audit_Level) return Boolean
   is
   begin
      return Severity <= Logger.Min_Severity;
   end Is_Active;

   procedure Log_Event
     (Logger   : in out Audit_Logger;
      Severity : Audit_Level;
      Domain   : Config_Domain;
      Detail   : Unsigned_64;
      Accepted : out Boolean)
   is
      pragma Unreferenced (Domain, Detail);
   begin
      Logger.Event_Count := Logger.Event_Count + 1;
      Accepted := Is_Active (Logger, Severity);
   end Log_Event;

   function Buffered_Events (Logger : Audit_Logger) return Natural
   is
      pragma Unreferenced (Logger);
   begin
      return 0;
   end Buffered_Events;

   procedure Read_Event
     (Logger : in out Audit_Logger;
      Event  : out Audit_Event)
   is
   begin
      Event := (Timestamp => 0, Severity => Emergency,
                Domain => Domain_Security, Event_ID => 0, Detail => 0);
   end Read_Event;

   procedure Initialize
     (Logger       : out Audit_Logger;
      Min_Severity : Audit_Level)
   is
   begin
      Logger.Buffer       := (others => (Timestamp => 0,
                                         Severity  => Emergency,
                                         Domain    => Domain_Security,
                                         Event_ID  => 0,
                                         Detail    => 0));
      Logger.Head         := 0;
      Logger.Tail         := 0;
      Logger.Event_Count  := 0;
      Logger.Overflows    := 0;
      Logger.Min_Severity := Min_Severity;
   end Initialize;

   -- Public scaffold: no persistent storage (no events are buffered here).
   procedure Persist_Audit_Log (Logger : in out Audit_Logger) is
      pragma Unreferenced (Logger);
   begin
      null;
   end Persist_Audit_Log;

end Schild_Audit_Logger;
