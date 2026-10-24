-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

package body Schild_MTF with SPARK_Mode => Off is

   function MTF_Period (S : MTF_Schedule) return Slot_Duration is
      Total : Slot_Duration := 0;
   begin
      for I in S'Range loop
         Total := Total + S (I).Duration;
      end loop;
      return Total;
   end MTF_Period;

   function Partition_For_Tick (S : MTF_Schedule; Tick : Tick_Count_Type)
     return Partition_Id is
      Period : constant Slot_Duration := MTF_Period (S);
      T      : Slot_Duration := 0;
   begin
      if Period = 0 then
         return S (S'First).Partition;
      end if;

      -- Position within the current Major Time Frame.
      T := Slot_Duration (Tick mod Tick_Count_Type (Period));

      -- Walk the slots to find the owning partition.
      for I in S'Range loop
         if T < S (I).Duration then
            return S (I).Partition;
         end if;
         T := T - S (I).Duration;
      end loop;

      -- Defensive fallback (unreachable for a well-formed schedule).
      return S (S'Last).Partition;
   end Partition_For_Tick;

end Schild_MTF;
