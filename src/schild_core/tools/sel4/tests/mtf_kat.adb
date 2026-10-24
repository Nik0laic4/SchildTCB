-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- =============================================================================
-- Known-answer test (KAT) for Schild_MTF (Major Time Frame).
-- Verifies the deterministic, static cyclic partition schedule.
-- Host-side program: run via run_mtf_kat.sh.
-- =============================================================================

with Ada.Command_Line;
with Ada.Text_IO;
with Schild_Timer; use Schild_Timer;
with Schild_MTF;    use Schild_MTF;

procedure Mtf_KAT is
   Failures : Natural := 0;

   procedure Check (Name : String; Actual, Expected : Partition_Id) is
   begin
      if Actual = Expected then
         Ada.Text_IO.Put_Line ("PASS  " & Name);
      else
         Ada.Text_IO.Put_Line
           ("FAIL  " & Name
            & "  got" & Partition_Id'Image (Actual)
            & "  want" & Partition_Id'Image (Expected));
         Failures := Failures + 1;
      end if;
   end Check;

begin
   -- Default schedule: 4 partitions x 25 ticks, period = 100 ticks.
   Check ("tick   0 -> P1", Partition_For_Tick (Default_Schedule, 0), 1);
   Check ("tick  24 -> P1", Partition_For_Tick (Default_Schedule, 24), 1);
   Check ("tick  25 -> P2", Partition_For_Tick (Default_Schedule, 25), 2);
   Check ("tick  49 -> P2", Partition_For_Tick (Default_Schedule, 49), 2);
   Check ("tick  50 -> P3", Partition_For_Tick (Default_Schedule, 50), 3);
   Check ("tick  75 -> P4", Partition_For_Tick (Default_Schedule, 75), 4);
   Check ("tick  99 -> P4", Partition_For_Tick (Default_Schedule, 99), 4);
   Check ("tick 100 -> P1 (wrap)", Partition_For_Tick (Default_Schedule, 100), 1);
   Check ("tick 125 -> P2 (wrap)", Partition_For_Tick (Default_Schedule, 125), 2);
   Check ("tick 199 -> P4", Partition_For_Tick (Default_Schedule, 199), 4);
   Check ("tick 200 -> P1", Partition_For_Tick (Default_Schedule, 200), 1);

   -- Period must be exactly 100 ticks.
   if MTF_Period (Default_Schedule) /= 100 then
      Ada.Text_IO.Put_Line
        ("FAIL  period =" & Slot_Duration'Image (MTF_Period (Default_Schedule)));
      Failures := Failures + 1;
   else
      Ada.Text_IO.Put_Line ("PASS  period = 100 ticks");
   end if;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("MTF KAT: ALL PASS (12 checks)");
   else
      Ada.Text_IO.Put_Line
        ("MTF KAT: " & Natural'Image (Failures) & " FAILED");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Mtf_KAT;
