-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- =============================================================================
-- Schild TCB — root-task orchestration launch model (ARINC 653 partition
-- lifecycle, "launch exactly once").
--
-- Pure decision bookkeeping, separated from the seL4 mechanism (retype / bind /
-- TCBWriteRegisters / TCBResume).  Mirrors Schild_HM_Model: the *policy* lives
-- here and carries formal SPARK contracts (Level 4); the *mechanism* stays in
-- Schild_Sel4_Syscall (SPARK_Mode => Off) at the seL4 boundary.
--
-- What is captured:
--   * launch: a domain is launched exactly once (one-shot, enforced by the
--     `not Launched` precondition of Launch);
--   * fault endpoints: a domain's fault endpoint is assigned exactly when it is
--     launched, fault-endpoint slots are pairwise distinct (a fault can never be
--     misrouted to another domain's handler), and each is non-zero;
--   * timeout endpoint: the shared timeout-fault endpoint (budget-overrun ->
--     seL4_Fault_Timeout) is bound exactly once, before any domain launches.
--
-- Invariant maintained across Bind_Timeout_EP and every Launch call.
-- =============================================================================

package Schild_Launch_Model with SPARK_Mode => On is

   -- The three seL4 partitions orchestrated by the root task.
   type Domain is (NetServer, MLS, Config_Daemon);

   -- One-shot launch bookkeeping.  Fault_EP(D) is the per-domain fault-endpoint
   -- slot (0 = not yet assigned); Timeout_EP is the shared timeout endpoint.
   type Launch_State is record
      Net_Launched   : Boolean := False;
      MLS_Launched   : Boolean := False;
      Cfg_Launched   : Boolean := False;
      Net_Fault_EP   : Natural := 0;
      MLS_Fault_EP   : Natural := 0;
      Cfg_Fault_EP   : Natural := 0;
      Timeout_EP     : Natural := 0;   -- shared timeout-fault endpoint slot
      Launched_Count : Natural := 0;
   end record;

   function Launched (S : Launch_State; D : Domain) return Boolean is
     (case D is
        when NetServer     => S.Net_Launched,
        when MLS           => S.MLS_Launched,
        when Config_Daemon => S.Cfg_Launched)
   with Global => null;

   function Fault_EP (S : Launch_State; D : Domain) return Natural is
     (case D is
        when NetServer     => S.Net_Fault_EP,
        when MLS           => S.MLS_Fault_EP,
        when Config_Daemon => S.Cfg_Fault_EP)
   with Global => null;

   function All_Launched (S : Launch_State) return Boolean is
     (for all D in Domain => Launched (S, D))
   with Global => null;

   -- State invariant:
   --   * a domain's fault endpoint is assigned (non-zero) iff it is launched;
   --   * fault-endpoint slots of distinct launched domains are pairwise
   --     distinct (no misrouting);
   --   * Launched_Count is exactly the number of launched domains (so it is
   --     always <= 3, which also bounds the +1 in Launch);
   --   * once any domain is launched, the shared timeout endpoint is bound.
   function Valid_State (S : Launch_State) return Boolean is
     ((for all D in Domain => (Fault_EP (S, D) > 0) = Launched (S, D))
      and then
      (for all D1 in Domain =>
         (for all D2 in Domain =>
            (if D1 /= D2 and then Launched (S, D1) and then Launched (S, D2)
             then Fault_EP (S, D1) /= Fault_EP (S, D2))))
      and then
      S.Launched_Count =
        (if S.Net_Launched then 1 else 0)
        + (if S.MLS_Launched then 1 else 0)
        + (if S.Cfg_Launched then 1 else 0)
      and then
      (if S.Launched_Count > 0 then S.Timeout_EP > 0))
   with Global => null;

   -- Bind the shared timeout-fault endpoint.  One-shot: must be called exactly
   -- once, before the first Launch.
   procedure Bind_Timeout_EP (S : in out Launch_State; Slot : Natural)
   with
     Pre  => Valid_State (S) and then S.Timeout_EP = 0 and then Slot > 0,
     Post => Valid_State (S) and then S.Timeout_EP = Slot;

   -- Record a domain launch together with its fault endpoint.  One-shot: a
   -- domain cannot be launched twice, and a fault-endpoint slot cannot be
   -- reused by two domains.  The shared timeout endpoint must already be bound
   -- (Bind_Timeout_EP) — containment relies on timeout faults naming a domain.
   procedure Launch
     (S          : in out Launch_State;
      D          : Domain;
      Fault_Slot : Natural)
   with
     Pre  => Valid_State (S)
             and then not Launched (S, D)
             and then S.Timeout_EP > 0
             and then Fault_Slot > 0
             and then (for all D2 in Domain =>
                         (if Launched (S, D2) then
                            Fault_EP (S, D2) /= Fault_Slot)),
     Post => Valid_State (S)
             and then Launched (S, D)
             and then Fault_EP (S, D) = Fault_Slot
             and then S.Launched_Count = S.Launched_Count'Old + 1
             and then (for all D2 in Domain =>
                         (if D2 /= D then
                            Launched (S, D2) = Launched (S'Old, D2)));

end Schild_Launch_Model;
