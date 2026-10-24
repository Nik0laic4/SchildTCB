-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- =============================================================================
-- Schild TCB — deterministic IPC ports (ARINC 653).
--   * Sampling_Port : single-slot, producer overwrites, consumer reads last value.
--   * Queuing_Port  : bounded SPSC FIFO ring (lock-free, fixed capacity).
-- No access types, no dynamic allocation — bounded and SPARK-checkable.
-- =============================================================================

with Interfaces; use Interfaces;

package Schild_IPC_Ports with SPARK_Mode => On is

   type Element is new Unsigned_64;

   Max_Capacity : constant := 64;

   ---------------------------------------------------------------------------
   -- Sampling port: holds the latest written value and a "fresh" flag.
   ---------------------------------------------------------------------------
   type Sampling_Port is record
      Data  : Element := 0;
      Fresh : Boolean := False;
   end record;

   -- Producer: overwrite the slot with the newest value.
   procedure Sample_Write (P : in out Sampling_Port; E : Element)
     with Post => P.Fresh and P.Data = E;

   -- Consumer: read the newest value and clear the freshness flag.
   procedure Sample_Read (P : in out Sampling_Port; E : out Element; Valid : out Boolean)
     with Post => Valid = P.Fresh'Old and E = P.Data'Old and not P.Fresh;

   ---------------------------------------------------------------------------
   -- Queuing port: bounded SPSC FIFO ring.
   ---------------------------------------------------------------------------
   type Queuing_Port is private;

   -- Producer: enqueue if there is room (deterministic, never blocks).
   procedure Queue_Send (P : in out Queuing_Port; E : Element; Success : out Boolean)
     with Post => Success = (Queue_Count (P)'Old < Max_Capacity);

   -- Consumer: dequeue if non-empty (deterministic, never blocks).
   procedure Queue_Receive (P : in out Queuing_Port; E : out Element; Success : out Boolean);

   function Queue_Count (P : Queuing_Port) return Natural
     with Post => Queue_Count'Result <= Max_Capacity;

   function Queue_Full (P : Queuing_Port) return Boolean is (Queue_Count (P) = Max_Capacity);
   function Queue_Empty (P : Queuing_Port) return Boolean is (Queue_Count (P) = 0);

private

   type Queue_Buffer is array (0 .. Max_Capacity - 1) of Element;

   type Queuing_Port is record
      Buf   : Queue_Buffer := (others => 0);
      Head  : Natural := 0;   -- consumer index
      Tail  : Natural := 0;   -- producer index
      Count : Natural := 0;   -- number of buffered elements
   end record
     with Type_Invariant =>
       Head < Max_Capacity and Tail < Max_Capacity and Count <= Max_Capacity;

end Schild_IPC_Ports;
