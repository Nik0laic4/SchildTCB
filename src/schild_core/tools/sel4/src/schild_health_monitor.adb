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

end Schild_Health_Monitor;
