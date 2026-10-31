-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- =============================================================================
-- Schild TCB Stage W9.3 — Hardware-independent Watchdog (kick / expire logic)
--
-- A countdown watchdog: the root task arms it with a period and must Kick it
-- before Countdown reaches zero. Tick is driven by the (deferred) hardware
-- timer interrupt; Expired reports a missed kick. The hardware timer itself
-- (x86 PIT/APIC, Pi BCM2711) is out of scope for the no-hardware phase — this
-- unit is the provable state machine the timer will drive.
-- =============================================================================

with Interfaces; use Interfaces;

package Schild_Watchdog
  with SPARK_Mode => On
is
   type Watchdog is record
      Countdown : Unsigned_64;  -- ticks remaining; 0 = expired
      Period    : Unsigned_64;  -- kick period in timer ticks
      Fired     : Boolean;      -- a kick was missed (Countdown reached 0)
   end record;

   -- Arm the watchdog with the given kick period (in timer ticks).
   procedure Initialize
     (W      : out Watchdog;
      Period :     Unsigned_64)
   with
     Pre  => Period > 0,
     Post => W.Period = Period
             and W.Countdown = Period
             and not W.Fired;

   -- Pet the watchdog: reset the countdown. Must be called before expiry.
   procedure Kick
     (W : in out Watchdog)
   with
     Pre  => not W.Fired,
     Post => W.Countdown = W.Period
             and W.Period = W.Period'Old
             and not W.Fired;

   -- Advance the watchdog by one timer tick; fires when Countdown reaches zero.
   procedure Tick
     (W : in out Watchdog)
   with
     Pre  => not W.Fired and W.Countdown > 0,
     Post => (if W.Countdown'Old = 1 then
                 W.Fired and W.Countdown = 0
              else
                 not W.Fired and W.Countdown = W.Countdown'Old - 1)
             and W.Period = W.Period'Old;

   -- True when the watchdog has fired (a kick was missed).
   function Expired (W : Watchdog) return Boolean
   with
     Post => Expired'Result = W.Fired;

end Schild_Watchdog;