-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

pragma Spark_Mode (On);

package body Schild_Health_Monitor is

   procedure Update_Health
     (Now         : Unsigned_64;
      Threshold   : Unsigned_64;
      Grace_Until : Word_Array_4;
      Last_Seen   : Word_Array_4;
      Health_Ok   : in out Bool_Array_4)
   is
   begin
      for D in 1 .. 4 loop
         pragma Loop_Invariant
           (for all J in 1 .. D - 1 =>
              (if Now > Grace_Until (J) and then Last_Seen (J) = 0
               then Health_Ok (J) = False));
         if Now > Grace_Until (D)
           and then (Last_Seen (D) = 0
                     or else Now - Last_Seen (D) > Threshold)
         then
            Health_Ok (D) := False;
         end if;
      end loop;
   end Update_Health;

   procedure Record_Heartbeat
     (Last_Seen : in out Word_Array_4;
      D         : Positive;
      Now       : Unsigned_64)
   is
   begin
      Last_Seen (D) := Now;
   end Record_Heartbeat;

   procedure Set_Grace
     (Grace_Until : in out Word_Array_4;
      D           : Positive;
      Deadline    : Unsigned_64)
   is
   begin
      Grace_Until (D) := Deadline;
   end Set_Grace;

   procedure Mark_Unhealthy
     (Health_Ok : in out Bool_Array_4;
      D         : Positive)
   is
   begin
      Health_Ok (D) := False;
   end Mark_Unhealthy;

end Schild_Health_Monitor;
