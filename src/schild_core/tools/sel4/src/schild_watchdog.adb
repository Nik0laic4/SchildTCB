-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

package body Schild_Watchdog
  with SPARK_Mode => On
is
   procedure Initialize
     (W      : out Watchdog;
      Period :     Unsigned_64)
   is
   begin
      W.Period    := Period;
      W.Countdown := Period;
      W.Fired     := False;
   end Initialize;

   procedure Kick
     (W : in out Watchdog)
   is
   begin
      W.Countdown := W.Period;
   end Kick;

   procedure Tick
     (W : in out Watchdog)
   is
   begin
      W.Countdown := W.Countdown - 1;
      if W.Countdown = 0 then
         W.Fired := True;
      end if;
   end Tick;

   function Expired (W : Watchdog) return Boolean is
   begin
      return W.Fired;
   end Expired;

end Schild_Watchdog;