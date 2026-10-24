-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- =============================================================================
-- Schild TCB Stage 7.2 — Audit Logger (Junos syslog-inspired)
--
-- Guaranteed delivery audit trail with ring buffer.
-- Severity levels: Emergency → Debug (RFC 5424 syslog).
-- =============================================================================

with Schild_Config_Daemon; use Schild_Config_Daemon;
with Interfaces;          use Interfaces;

package Schild_Audit_Logger
  with SPARK_Mode => On
is
   -- Audit event
   type Audit_Event is record
      Timestamp : Unsigned_64;  -- monotonic ticks
      Severity  : Audit_Level;
      Domain    : Config_Domain;
      Event_ID  : Unsigned_64;  -- sequential event number
      Detail    : Unsigned_64;  -- domain-specific data
   end record;

   -- Ring buffer
   Buffer_Size : constant := 64;  -- power of 2 for fast wrap
   type Audit_Buffer is array (0 .. Buffer_Size - 1) of Audit_Event;

   type Audit_Logger is record
      Buffer      : Audit_Buffer;
      Head        : Natural range 0 .. Buffer_Size - 1;  -- write position
      Tail        : Natural range 0 .. Buffer_Size - 1;  -- read position
      Event_Count : Unsigned_64;  -- total events since boot
      Overflows   : Unsigned_64;  -- times buffer wrapped
      Min_Severity : Audit_Level; -- filter: log only >= this level
   end record;

   -- Severity ordering (Emergency most severe, Debug least)
   function Is_Active (Logger : Audit_Logger; Severity : Audit_Level) return Boolean
   with
     Post => Is_Active'Result = (Severity <= Logger.Min_Severity);

   -- Log an event (returns False if event was dropped due to severity filter)
   procedure Log_Event
     (Logger   : in out Audit_Logger;
      Severity : Audit_Level;
      Domain   : Config_Domain;
      Detail   : Unsigned_64;
      Accepted : out Boolean)
   with
     Post => Logger.Event_Count = Logger.Event_Count'Old + 1;

   -- Number of events currently in buffer
   function Buffered_Events (Logger : Audit_Logger) return Natural;

   -- Read oldest event from buffer (caller must check Buffered_Events > 0)
   procedure Read_Event
     (Logger : in out Audit_Logger;
      Event  : out Audit_Event)
   with
     Pre => Buffered_Events (Logger) > 0;

   -- Initialize logger with severity threshold
   procedure Initialize
     (Logger       : out Audit_Logger;
      Min_Severity : Audit_Level)
   with
     Post => Logger.Event_Count = 0 and Logger.Overflows = 0;

end Schild_Audit_Logger;
