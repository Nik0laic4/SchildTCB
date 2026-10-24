-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- =============================================================================
-- Known-answer test (KAT) for the two-level schedule (MTF + priority).
-- Verifies Find_Next_Task_In_Partition and its composition with Partition_For_Tick.
-- Host-side program: run via run_two_level_kat.sh.
-- =============================================================================

with Ada.Command_Line;
with Ada.Text_IO;
with Schild_Timer;     use Schild_Timer;
with Schild_MTF;       use Schild_MTF;
with Schild_Scheduler; use Schild_Scheduler;

procedure Two_Level_KAT is
   Failures : Natural := 0;

   procedure Check (Name : String; Cond : Boolean) is
   begin
      if Cond then
         Ada.Text_IO.Put_Line ("PASS  " & Name);
      else
         Ada.Text_IO.Put_Line ("FAIL  " & Name);
         Failures := Failures + 1;
      end if;
   end Check;

   Sched : Scheduler_Type;
   P     : Partition_Id;
   Next  : Task_Id;

begin
   -- Partition 1: tasks 1 (pri 10) and 2 (pri 20).
   Sched.Tasks (1) := (State => Task_Ready, Priority => 10,
                       Partition => 1, Context => (others => 0));
   Sched.Tasks (2) := (State => Task_Ready, Priority => 20,
                       Partition => 1, Context => (others => 0));
   -- Partition 2: task 3 (pri 5).
   Sched.Tasks (3) := (State => Task_Ready, Priority => 5,
                       Partition => 2, Context => (others => 0));
   -- Partition 3: task 4 blocked (must NOT be selected).
   Sched.Tasks (4) := (State => Task_Blocked, Priority => 100,
                       Partition => 3, Context => (others => 0));

   Next := Find_Next_Task_In_Partition (Sched, 1);
   Check ("partition 1 -> task 2 (pri 20)", Next = 2);

   Next := Find_Next_Task_In_Partition (Sched, 2);
   Check ("partition 2 -> task 3 (pri 5)", Next = 3);

   Next := Find_Next_Task_In_Partition (Sched, 3);
   Check ("partition 3 -> 0 (blocked)", Next = 0);

   -- Two-level composition: MTF tick -> partition -> priority task.
   P := Partition_For_Tick (Default_Schedule, 0);   -- tick 0  -> P1
   Next := Find_Next_Task_In_Partition (Sched, P);
   Check ("tick 0 -> P1 -> task 2", P = 1 and then Next = 2);

   P := Partition_For_Tick (Default_Schedule, 25);  -- tick 25 -> P2
   Next := Find_Next_Task_In_Partition (Sched, P);
   Check ("tick 25 -> P2 -> task 3", P = 2 and then Next = 3);

   P := Partition_For_Tick (Default_Schedule, 50);  -- tick 50 -> P3 (empty)
   Next := Find_Next_Task_In_Partition (Sched, P);
   Check ("tick 50 -> P3 -> 0 (idle)", P = 3 and then Next = 0);

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("Two-level KAT: ALL PASS");
   else
      Ada.Text_IO.Put_Line
        ("Two-level KAT: " & Natural'Image (Failures) & " FAILED");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end Two_Level_KAT;
