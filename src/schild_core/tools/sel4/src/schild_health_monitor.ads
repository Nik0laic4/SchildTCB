-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only
--
-- Schild TCB — C9 liveness-detect health monitor (proved slice).
-- The stale->unhealthy detect is provable in isolation; the heartbeat/grace/
-- timeout/probe side-effects live in the root task.

with Interfaces; use Interfaces;

package Schild_Health_Monitor
  with SPARK_Mode => On
is
   type Word_Array_4 is array (1 .. 4) of Unsigned_64;
   type Bool_Array_4 is array (1 .. 4) of Boolean;

   --  Mark a domain unhealthy when its grace deadline has passed and it has
   --  never beaten (Last_Seen = 0). The runtime body also checks the
   --  stale-past-threshold arm (Now - Last_Seen > Threshold), which is outside
   --  the proved Post (modular subtraction over Unsigned_64).
   procedure Update_Health
     (Now         : Unsigned_64;
      Threshold   : Unsigned_64;
      Grace_Until : Word_Array_4;
      Last_Seen   : Word_Array_4;
      Health_Ok   : in out Bool_Array_4)
     with Global => null,
          Post => (for all D in 1 .. 4 =>
                     (if Now > Grace_Until (D) and then Last_Seen (D) = 0
                      then Health_Ok (D) = False));
end Schild_Health_Monitor;
