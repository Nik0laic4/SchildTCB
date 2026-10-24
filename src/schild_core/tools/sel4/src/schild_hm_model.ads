-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- =============================================================================
-- Schild TCB — ARINC 653 Health Monitoring: partition lifecycle model.
--
-- Pure decision logic, separated from the seL4 mechanism (retype / bind /
-- TCBWriteRegisters / TCBResume). The lifecycle carries formal SPARK contracts
-- (Level 4):
--
--   launch:   a domain is launched exactly once (one-shot, monotonic);
--   fault:    a domain can fault only after it has been launched;
--   process level:   count <= Max_Restarts            -> RESTART the domain;
--   partition level: count  > Max_Restarts            -> STOP the domain;
--   module level:    every domain escalated to STOP   -> MODULE IDLE.
--
-- Escalation is monotonic: a domain is marked "stopped" exactly once its fault
-- count exceeds Max_Restarts, a stopped domain is never restarted again, and a
-- domain can only be stopped if it was launched first.
-- =============================================================================

package Schild_HM_Model with SPARK_Mode => On is

   type HM_Domain is (HM_NetServer, HM_MLS, HM_Config_Daemon);

   -- Consecutive transient faults tolerated before escalation from process
   -- level (RESTART) to partition level (STOP).
   Max_Restarts : constant Natural := 1;

   type Fault_Counters is record
      Net : Natural := 0;
      MLS : Natural := 0;
      Cfg : Natural := 0;
   end record;

   type HM_State is record
      Counts       : Fault_Counters;
      Net_Stopped  : Boolean := False;
      MLS_Stopped  : Boolean := False;
      Cfg_Stopped  : Boolean := False;
      Net_Launched : Boolean := False;
      MLS_Launched : Boolean := False;
      Cfg_Launched : Boolean := False;
   end record;

   -- Health-monitor action the caller must perform for a reported fault.
   type HM_Action is (Restart, Stop, Module_Idle);

   function Count (State : HM_State; Domain : HM_Domain) return Natural is
     (case Domain is
        when HM_NetServer     => State.Counts.Net,
        when HM_MLS           => State.Counts.MLS,
        when HM_Config_Daemon => State.Counts.Cfg)
   with Global => null;

   function Stopped (State : HM_State; Domain : HM_Domain) return Boolean is
     (case Domain is
        when HM_NetServer     => State.Net_Stopped,
        when HM_MLS           => State.MLS_Stopped,
        when HM_Config_Daemon => State.Cfg_Stopped)
   with Global => null;

   function Launched (State : HM_State; Domain : HM_Domain) return Boolean is
     (case Domain is
        when HM_NetServer     => State.Net_Launched,
        when HM_MLS           => State.MLS_Launched,
        when HM_Config_Daemon => State.Cfg_Launched)
   with Global => null;

   function All_Stopped (State : HM_State) return Boolean is
     (for all D in HM_Domain => Stopped (State, D))
   with Global => null;

   -- State invariant:
   --   * a domain is marked stopped iff its fault count exceeded Max_Restarts;
   --   * a domain can only be stopped if it was launched first.
   -- Maintained across every Launch and Evaluate call.
   function Valid_State (State : HM_State) return Boolean is
     ((for all D in HM_Domain =>
         (Stopped (State, D) = (Count (State, D) > Max_Restarts)))
      and then
      (for all D in HM_Domain =>
         (if Stopped (State, D) then Launched (State, D))))
   with Global => null;

   -- Record that a domain has been launched.  One-shot: a domain cannot be
   -- launched twice.
   procedure Launch (State : in out HM_State; Domain : HM_Domain)
   with
     Pre  => Valid_State (State) and then not Launched (State, Domain),
     Post => Valid_State (State)
             and then Launched (State, Domain)
             and then
             (for all D in HM_Domain =>
                (if D /= Domain then
                   Launched (State, D) = Launched (State'Old, D)));

   -- Record a fault for a launched Domain and choose the required action.
   procedure Evaluate
     (State  : in out HM_State;
      Domain : HM_Domain;
      Action : out HM_Action)
   with
     Pre  => Valid_State (State)
             and then Launched (State, Domain)
             and then Count (State, Domain) < Natural'Last,
     Post => Valid_State (State)
             and then
             -- Exactly the faulted domain's counter is incremented by one.
             Count (State, Domain) = Count (State'Old, Domain) + 1
             and then
             (for all D in HM_Domain =>
                (if D /= Domain then Count (State, D) = Count (State'Old, D)))
             and then
             -- The action follows the ARINC 653 escalation rules.
             (if All_Stopped (State) then Action = Module_Idle
              elsif Count (State, Domain) > Max_Restarts then Action = Stop
              else Action = Restart);

end Schild_HM_Model;
