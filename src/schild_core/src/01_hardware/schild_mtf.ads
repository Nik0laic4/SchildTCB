-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- =============================================================================
-- Schild TCB — Major Time Frame (ARINC 653) static cyclic schedule.
-- Replaces the dynamic priority scan with a fixed, deterministic partition
-- matrix: each partition owns a fixed time window, repeated cyclically.
-- =============================================================================

with Schild_Timer; use Schild_Timer;
with Interfaces;   use Interfaces;

package Schild_MTF with SPARK_Mode => Off is

   Max_Partitions : constant := 4;
   subtype Partition_Id is Positive range 1 .. Max_Partitions;

   -- Duration of one partition window, in PIT ticks (~10 ms each @ 100 Hz).
   type Slot_Duration is new Unsigned_32;

   type MTF_Slot is record
      Partition : Partition_Id;
      Duration  : Slot_Duration;
   end record;

   type MTF_Schedule is array (Positive range <>) of MTF_Slot;

   -- Default Major Time Frame: 4 partitions, 25 ticks each (~250 ms window).
   Default_Schedule : constant MTF_Schedule :=
     (1 => (Partition => 1, Duration => 25),
      2 => (Partition => 2, Duration => 25),
      3 => (Partition => 3, Duration => 25),
      4 => (Partition => 4, Duration => 25));

   -- Total duration of one Major Time Frame (sum of all slots).
   function MTF_Period (S : MTF_Schedule) return Slot_Duration;

   -- Partition that owns the given tick within the cyclic schedule.
   function Partition_For_Tick (S : MTF_Schedule; Tick : Tick_Count_Type)
     return Partition_Id;

end Schild_MTF;
