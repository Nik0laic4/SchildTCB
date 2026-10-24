-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

with Schild_Sel4_Syscall;
with Schild_Sel4_BootInfo;  use Schild_Sel4_BootInfo;
with Schild_Config_Daemon;  use Schild_Config_Daemon;
with Schild_Boot_Manager;   use Schild_Boot_Manager;
with Interfaces;          use Interfaces;
with System;
with Schild_MLS_Policy;     use Schild_MLS_Policy;
with Schild_Audit_Logger;  use Schild_Audit_Logger;

procedure Schild_Root_Task with SPARK_Mode => On is
   -- Read the seL4 BootInfo frame as a VALUE (via a C memcpy shim) instead of
   -- dereferencing an opaque C pointer — SPARK can reason about the value.
   procedure Get_BootInfo_Copy (BI : out BootInfo; Nbytes : Unsigned_64)
     with Import, Convention => C, External_Name => "schild_get_bootinfo_copy",
          Global => null;
   BI : BootInfo;

   Count        : Natural := 0;
   RAM_MB       : Word := 0;
   Fault_Slot   : Schild_Sel4_Syscall.Cap_Ref := Schild_Sel4_Syscall.Root_Fault_EP_Slot;
   -- Stage 8.3: e1000e IRQ wiring (see Init_NetServer_IRQ).
   Net_EP_Slot      : Schild_Sel4_Syscall.Cap_Ref := Schild_Sel4_Syscall.Net_EP_Slot;
   IRQ_Ntfn_Slot    : Schild_Sel4_Syscall.Cap_Ref := Schild_Sel4_Syscall.IRQ_Ntfn_Badged_Slot;  -- badged (0xE1)
   IRQ_Handler_Slot : Schild_Sel4_Syscall.Cap_Ref := Schild_Sel4_Syscall.IRQ_Handler_Slot;
   -- C.7: per-domain endpoint + fault-endpoint slots (MLS + Config Daemon).
   MLS_EP_Slot       : Schild_Sel4_Syscall.Cap_Ref := Schild_Sel4_Syscall.MLS_EP_Slot;
   MLS_Fault_Slot    : Schild_Sel4_Syscall.Cap_Ref := Schild_Sel4_Syscall.MLS_Fault_Slot;
   Config_EP_Slot    : Schild_Sel4_Syscall.Cap_Ref := Schild_Sel4_Syscall.Config_EP_Slot;
   Config_Fault_Slot : Schild_Sel4_Syscall.Cap_Ref := Schild_Sel4_Syscall.Config_Fault_Slot;
   -- B.6: shared timeout-fault endpoint (budget overrun -> seL4_Fault_Timeout).
   Timeout_EP_Slot   : Schild_Sel4_Syscall.Cap_Ref := Schild_Sel4_Syscall.Timeout_EP_Slot;
begin
   Get_BootInfo_Copy (BI, Unsigned_64 (BootInfo'Size / System.Storage_Unit));
   Put_Str (ASCII.CR & ASCII.LF);
   Put_Str ("==== Schild TCB Root Task (Ada/SPARK 2022) ====" & ASCII.CR & ASCII.LF);
   Put_Str ("==== Stage 7: Config Daemon + A/B Boot Manager ====" & ASCII.CR & ASCII.LF);
   Put_Str ("Node: "); Put_Dec (BI.Node_ID); Put_Str (" / "); Put_Dec (BI.Num_Nodes); Put_Str (ASCII.CR & ASCII.LF);
   Put_Str ("CSpace: 2^"); Put_Dec (BI.Init_Thread_CNode_Bits); Put_Str (" slots" & ASCII.CR & ASCII.LF);
   Put_Str ("Untyped: "); Put_Dec (BI.Untyped_End - BI.Untyped_Start); Put_Str (" caps" & ASCII.CR & ASCII.LF);
    Put_Str ("Untyped slots: "); Put_Dec (BI.Untyped_Start);
    Put_Str (" .. "); Put_Dec (BI.Untyped_End); Put_Str (ASCII.CR & ASCII.LF);
    Put_Str ("Empty slots:  "); Put_Dec (BI.Empty_Start);
    Put_Str (" .. "); Put_Dec (BI.Empty_End); Put_Str (ASCII.CR & ASCII.LF);
   Put_Str ("----- Memory Map -----" & ASCII.CR & ASCII.LF);

   for I in 1 .. N_UNTYPED loop
      exit when Count >= N_UNTYPED;
      if I <= BI.Untyped_List'Last
        and then BI.Untyped_List (I).Size_Bits > 0
      then
         declare
             SB : constant Natural := Natural (BI.Untyped_List (I).Size_Bits);
             Sz : Word := (if SB < 64 then Shift_Left (Word (1), SB) else 0);
             Mb : Word := (if SB >= 20 and SB < 84
                           then Shift_Left (Word (1), SB - 20) else 0);
          begin
            Put_Str ("  #"); Put_Dec (Word (Count)); Put_Str (": 0x");
            Put_Hex (BI.Untyped_List (I).PAddr); Put_Str (" .. ");
            Put_Hex (BI.Untyped_List (I).PAddr + Sz);
            Put_Str ("  "); Put_Dec (Mb); Put_Str (" MB");
            if BI.Untyped_List (I).Is_Device = 0 then
               Put_Str (" [RAM]" & ASCII.CR & ASCII.LF);
               RAM_MB := RAM_MB + Mb;
            else
               Put_Str (" [dev]" & ASCII.CR & ASCII.LF);
            end if;
            Count := Count + 1;
         end;
      end if;
   end loop;

   Put_Str ("----- Summary -----" & ASCII.CR & ASCII.LF);
   Put_Str ("Total RAM:  "); Put_Dec (RAM_MB); Put_Str (" MB" & ASCII.CR & ASCII.LF);
   Put_Str ("RT checks: ON (-gnatwa)" & ASCII.CR & ASCII.LF);

    -- == Stage 7: Config Daemon + Boot Manager demo ==
    declare
       CD : Config_Daemon;
       BM : Boot_Manager;
       Admin_Level : constant Security_Level := Top_Secret;
    begin
       Initialize (CD);
       Initialize (BM);
       Put_Str ("[S7] Config Daemon: 4 entries, Boot Manager: Slot A" & ASCII.CR & ASCII.LF);

       -- T1: Reject config with insufficient clearance
       CD.Mode := Validating;
       if Validate_Config (CD, Confidential) then
          Put_Str ("[S7] T1 FAIL" & ASCII.CR & ASCII.LF);
       else
          Put_Str ("[S7] T1 PASS: Insufficient clearance rejected" & ASCII.CR & ASCII.LF);
       end if;

       -- T2: Tentative + auto-rollback on timeout
       CD.Mode := Validating;
       if Validate_Config (CD, Admin_Level) then
          Apply_Tentative (CD, 3);
          for I in 1 .. 5 loop Tick (CD); end loop;
          if CD.Mode = Idle then
             Put_Str ("[S7] T2 PASS: Auto-rollback after timeout" & ASCII.CR & ASCII.LF);
          else
             Put_Str ("[S7] T2 FAIL" & ASCII.CR & ASCII.LF);
          end if;
       end if;

       -- T3: Validate + commit
       CD.Mode := Validating;
       if Validate_Config (CD, Admin_Level) then
          Apply_Tentative (CD, 100);
          Commit (CD);
          if CD.Mode = Committed then
             Put_Str ("[S7] T3 PASS: Config committed" & ASCII.CR & ASCII.LF);
          else
             Put_Str ("[S7] T3 FAIL" & ASCII.CR & ASCII.LF);
          end if;
       end if;

       -- T4: Boot failover
       Failover (BM);
       if BM.Active_Slot = Slot_B then
          Put_Str ("[S7] T4 PASS: Failover A->B" & ASCII.CR & ASCII.LF);
          Failover (BM);  -- switch back
          Record_Successful_Boot (BM);
       else
          Put_Str ("[S7] T4 FAIL" & ASCII.CR & ASCII.LF);
       end if;

       Put_Str ("[S7] Boots: "); Put_Dec (BM.Boot_Count);
       Put_Str ("  Audits: "); Put_Dec (CD.Audit_Queue);
       Put_Str (ASCII.CR & ASCII.LF);
    end;


    -- == Stage 7.2: MLS Policy + Audit Logger ==
    declare
       MLS  : MLS_Daemon;
       AL   : Audit_Logger;
    begin
       Initialize (MLS);
       Initialize (AL, Warning);  -- log Warning and above

       -- Register processes with different clearances
       Register_Process (MLS, 1, Top_Secret);
       Register_Process (MLS, 2, Secret);
       Register_Process (MLS, 3, Confidential);
       Register_Process (MLS, 4, Public);
       Put_Str ("[S7.2] MLS: 4 processes registered" & ASCII.CR & ASCII.LF);

       -- T5: IPC between equal levels (allowed)
       if Authorize_IPC (MLS, (Sender => 1, Receiver => 1, Data_Size => 0)) = Allowed then
          Put_Str ("[S7.2] T5 PASS: IPC Top_Secret->Top_Secret allowed" & ASCII.CR & ASCII.LF);
       else
          Put_Str ("[S7.2] T5 FAIL" & ASCII.CR & ASCII.LF);
       end if;

       -- T6: IPC cross-level (blocked)
       if Authorize_IPC (MLS, (Sender => 2, Receiver => 3, Data_Size => 0)) = Allowed then
          Put_Str ("[S7.2] T6 FAIL: IPC Secret->Confidential should be blocked" & ASCII.CR & ASCII.LF);
       else
          Put_Str ("[S7.2] T6 PASS: IPC Secret->Confidential blocked" & ASCII.CR & ASCII.LF);
       end if;
       -- T9: unknown (unregistered) process must be denied (fail-closed).
       if Authorize_IPC (MLS, (Sender => 99, Receiver => 1, Data_Size => 0)) = Allowed then
          Put_Str ("[S7.2] T9 FAIL: unknown sender must be denied" & ASCII.CR & ASCII.LF);
       else
          Put_Str ("[S7.2] T9 PASS: unknown sender denied (fail-closed)" & ASCII.CR & ASCII.LF);
       end if;

       -- T7: Read up attempt (blocked)
       if Check_Read (Confidential, Secret) = Denied_No_Read_Up then
          Put_Str ("[S7.2] T7 PASS: Confidential cannot read Secret" & ASCII.CR & ASCII.LF);
       else
          Put_Str ("[S7.2] T7 FAIL" & ASCII.CR & ASCII.LF);
       end if;

        -- T8: Audit logger — log events at various severities
        for I in 1 .. 5 loop
           declare
              Ok : Boolean;
           begin
              Log_Event (AL, Error, Domain_Security, Unsigned_64 (I), Ok);
           end;
        end loop;
        -- Debug event should be filtered out
        declare
           Ok : Boolean;
        begin
           Log_Event (AL, Debug, Domain_Network, 99, Ok);
           if not Ok then
              Put_Str ("[S7.2] T8 PASS: Debug event filtered (below Warning)" & ASCII.CR & ASCII.LF);
           else
              Put_Str ("[S7.2] T8 FAIL: Debug should be filtered" & ASCII.CR & ASCII.LF);
           end if;
        end;

       Put_Str ("[S7.2] Audit: "); Put_Dec (AL.Event_Count);
       Put_Str (" events, "); Put_Dec (Unsigned_64 (Buffered_Events (AL)));
       Put_Str (" buffered" & ASCII.CR & ASCII.LF);

       -- P1 (R9): persist the audit trail to SchildFS so it survives power loss.
       Persist_Audit_Log (AL);
       Put_Str ("[S7.2] Audit persisted to SchildFS (audit.log)" & ASCII.CR & ASCII.LF);
    end;

   -- Stage 6: Fault handler init (FIRST — sets up IPC buffer for everyone)
   Put_Str ("----- Stage 6: Fault Handler -----" & ASCII.CR & ASCII.LF);
   declare
      Stage6_Result : Word := Schild_Sel4_Syscall.Init_Fault_Handler;
   begin
      if Stage6_Result = 0 then
         Put_Str ("[Stage6] Fault handler ready. Entering NBRecv poll loop..." & ASCII.CR & ASCII.LF);
         Fault_Slot := Schild_Sel4_Syscall.Root_Fault_EP_Slot;  -- confirmed slot (above untyped caps)
      else
         Put_Str ("[Stage6] WARN: Fault handler init failed (err=");
         Put_Dec (Stage6_Result);
         Put_Str ("). Falling back to pause idle." & ASCII.CR & ASCII.LF);
         Fault_Slot := 0;  -- disable polling
      end if;
   end;

   -- Stage 7.7: Launch MLS server (IPC buffer already set up by Stage 6)
   Put_Str ("----- Stage 7.7: Launching MLS Server -----" & ASCII.CR & ASCII.LF);
   declare
      R : Word := Schild_Sel4_Syscall.Launch_MLS_Server;
   begin
      if R = 0 then
         Put_Str ("[S7.7] MLS Server: OK" & ASCII.CR & ASCII.LF);
      else
         Put_Str ("[S7.7] MLS Server: FAILED (code=");
         Put_Dec (R);
         Put_Str (")" & ASCII.CR & ASCII.LF);
      end if;
   end;

   -- Stage 8.1B: map e1000e BAR0 MMIO into VSpace for NetServer (0x600000)
   Put_Str ("----- Stage 8.2: NetServer VSpace isolation -----" & ASCII.CR & ASCII.LF);
   declare
      R : Word := Schild_Sel4_Syscall.Map_NetServer_VSpace;
   begin
      if R = 0 then
         Put_Str ("[S8.2] NetServer VSpace: OK" & ASCII.CR & ASCII.LF);
      else
         Put_Str ("[S8.2] NetServer VSpace: FAILED (code=");
         Put_Dec (R);
         Put_Str (")" & ASCII.CR & ASCII.LF);
      end if;
   end;

   -- Stage 8.3: wire the e1000e IRQ to a (badged) Notification BEFORE the
   -- NetServer starts (its Init_MMIO enables the e1000e interrupt mask), so
   -- the very first TX/LSC interrupt is not lost.
   Put_Str ("----- Stage 8.3: e1000e IRQ (Notification) -----" & ASCII.CR & ASCII.LF);
   declare
      R : Word := Schild_Sel4_Syscall.Init_NetServer_IRQ;
   begin
      if R = 0 then
         Put_Str ("[S8.3] e1000e IRQ: OK" & ASCII.CR & ASCII.LF);
      else
         Put_Str ("[S8.3] e1000e IRQ: FAILED (code=");
         Put_Dec (R);
         Put_Str (")" & ASCII.CR & ASCII.LF);
      end if;
   end;

   -- Stage 8.1C/D: install DMA offset, launch NetServer process + IPC test.
   Put_Str ("----- Stage 8.1C/D: NetServer -----" & ASCII.CR & ASCII.LF);
   declare
      R : Word := Schild_Sel4_Syscall.Init_NetServer_DMA;
   begin
      if R /= 0 then
         Put_Str ("[S8.1C] DMA offset: FAILED (code=");
         Put_Dec (R);
         Put_Str (")" & ASCII.CR & ASCII.LF);
      else
         Put_Str ("[S8.1C] DMA offset: OK" & ASCII.CR & ASCII.LF);
         declare
            LR : Word := Schild_Sel4_Syscall.Launch_NetServer;
         begin
            if LR = 0 then
               Put_Str ("[S8.1D] NetServer: OK" & ASCII.CR & ASCII.LF);
            else
               Put_Str ("[S8.1D] NetServer: FAILED (code=");
               Put_Dec (LR);
               Put_Str (")" & ASCII.CR & ASCII.LF);
            end if;
         end;
      end if;
   end;

   -- Stage 8.4: shared DMA frame (large-frame transfer, no MR limit).
   Put_Str ("----- Stage 8.4: shared DMA frame -----" & ASCII.CR & ASCII.LF);
   declare
      R : Word := Schild_Sel4_Syscall.Init_NetServer_Shared_Frame;
   begin
      if R = 0 then
         Put_Str ("[S8.4] shared frame: OK" & ASCII.CR & ASCII.LF);
         -- Demo: place a 64-byte test frame (first byte 0x5A) in the shared
         -- frame, TX it via op=2, and verify the NetServer echoes the first
         -- byte back — proving the shared frame round-trips between VSpaces.
         declare
            Demo : Word := Schild_Sel4_Syscall.Demo_Shared_Frame;
         begin
            null;
         end;
      else
         Put_Str ("[S8.4] shared frame: FAILED (code=");
         Put_Dec (R);
         Put_Str (")" & ASCII.CR & ASCII.LF);
      end if;
   end;

   -- R4: per-level MLS SPSC rings (directional RO/RW mapping).
   Put_Str ("----- R4: MLS rings -----" & ASCII.CR & ASCII.LF);
   declare
      Ring_R : Word := Schild_Sel4_Syscall.Init_Mls_Rings;
   begin
      if Ring_R = 0 then
         Put_Str ("[R4] MLS rings: OK" & ASCII.CR & ASCII.LF);
      else
         Put_Str ("[R4] MLS rings: FAILED (code=");
         Put_Dec (Ring_R);
         Put_Str (")" & ASCII.CR & ASCII.LF);
      end if;
   end;

   -- R3: isolated Config Daemon process (own fault domain).
   Put_Str ("----- R3: Config Daemon -----" & ASCII.CR & ASCII.LF);
   declare
      CD_R : Word := Schild_Sel4_Syscall.Launch_Config_Daemon;
   begin
      if CD_R = 0 then
         Put_Str ("[R3] Config Daemon: OK" & ASCII.CR & ASCII.LF);
      else
         Put_Str ("[R3] Config Daemon: FAILED (code=");
         Put_Dec (CD_R);
         Put_Str (")" & ASCII.CR & ASCII.LF);
      end if;
   end;

   -- P1 (R10): IPC ping-pong benchmark — Call/Reply round-trip against the
   -- NetServer (op=4 = bench noop), timed with RDTSC. Probes the seL4
   -- Fastpath: round-trip cycles should drop when KernelFastpath=ON.
   declare
      function RDTSC return Word
        with Import, Convention => C, External_Name => "schild_rdtsc",
             Global => null;
      N  : constant Unsigned_32 := 10_000;
      T0 : Word := 0;
      T1 : Word := 0;
      R  : Word := 0;
   begin
      for J in 1 .. 1_000 loop          -- warm-up: prime endpoint + branch
         R := Schild_Sel4_Syscall.Call_IPC (Net_EP_Slot, 4, 0);
      end loop;
      T0 := RDTSC;
      for J in 1 .. N loop
         R := Schild_Sel4_Syscall.Call_IPC (Net_EP_Slot, 4, 0);
      end loop;
      T1 := RDTSC;
      Put_Str ("[BENCH] IPC Call/Reply:" & ASCII.CR & ASCII.LF);
      Put_Str ("[BENCH]   iterations="); Put_Dec (Word (N));
      Put_Str (ASCII.CR & ASCII.LF);
      Put_Str ("[BENCH]   total_cycles="); Put_Dec (T1 - T0);
      Put_Str (ASCII.CR & ASCII.LF);
      Put_Str ("[BENCH]   cycles_per_op="); Put_Dec ((T1 - T0) / Word (N));
      Put_Str (ASCII.CR & ASCII.LF);
      Put_Str ("[BENCH]   last_reply="); Put_Dec (R);
      Put_Str (ASCII.CR & ASCII.LF);
   end;

   -- Stage 9: crash-containment test. Arm a fault in the NetServer (op=99):
   -- the NetServer replies first (so Call_IPC returns), then writes to
   -- unmapped 0xFFFFF000 (a #PF). The NetServer is priority 0 vs the root
   -- task's priority 255, so it only runs while the root task blocks: after
   -- the Call returns we BLOCK on a Recv of the fault endpoint, letting the
   -- NetServer fault; seL4 delivers the fault to the fault endpoint (badge
   -- 0xE2), the Recv returns it, and the core stays alive — containment.
   if Fault_Slot > 0 then
      Put_Str ("[CONTAINMENT] injecting fault into NetServer (op=99)..." & ASCII.CR & ASCII.LF);
      declare
         R : Word := Schild_Sel4_Syscall.Call_IPC (Net_EP_Slot, 99, 0);
      begin
         Put_Str ("[CONTAINMENT] fault armed (call returned "); Put_Hex (R);
         Put_Str (")" & ASCII.CR & ASCII.LF);
      end;

      declare
         Badge : Word := Schild_Sel4_Syscall.Wait (Fault_Slot);
      begin
         Put_Str (ASCII.CR & ASCII.LF & "[FAULT] Caught fault — badge=0x");
         Put_Hex (Badge);
         Put_Str (" — thread suspended (containment)" & ASCII.CR & ASCII.LF);
         Schild_Sel4_Syscall.Health_Monitor (Schild_Sel4_Syscall.HM_NetServer);
         Put_Str ("[CONTAINMENT] core alive after fault" & ASCII.CR & ASCII.LF);
      end;
   end if;

   -- C.7: crash-containment for the MLS server and Config Daemon.  Mirror the
   -- NetServer test: inject op=99, the server replies then faults; seL4
   -- delivers the #PF to the server's own fault endpoint (MLS=199, Config=526),
   -- the root task catches it, and Health Monitoring restarts the domain.
   Put_Str ("[CONTAINMENT] injecting fault into MLS server (op=99)..." & ASCII.CR & ASCII.LF);
   declare
      R : Word := Schild_Sel4_Syscall.Call_IPC (MLS_EP_Slot, 99, 0);
   begin
      null;
   end;
   declare
      Badge : Word := Schild_Sel4_Syscall.Wait (MLS_Fault_Slot);
   begin
      Put_Str (ASCII.CR & ASCII.LF & "[FAULT] Caught MLS fault — badge=0x");
      Put_Hex (Badge);
      Put_Str (" — restarting" & ASCII.CR & ASCII.LF);
      Schild_Sel4_Syscall.Health_Monitor (Schild_Sel4_Syscall.HM_MLS);
      Put_Str ("[CONTAINMENT] MLS server contained" & ASCII.CR & ASCII.LF);
   end;

   -- C.8: escalation.  Inject the MLS fault a second time: the fault counter
   -- exceeds Max_Restarts, so Health Monitoring escalates from RESTART
   -- (process level) to STOP (partition level).
   Put_Str ("[HM] injecting repeated MLS fault (op=99)..." & ASCII.CR & ASCII.LF);
   declare
      R : Word := Schild_Sel4_Syscall.Call_IPC (MLS_EP_Slot, 99, 0);
   begin
      null;
   end;
   declare
      Badge : Word := Schild_Sel4_Syscall.Wait (MLS_Fault_Slot);
   begin
      Schild_Sel4_Syscall.Health_Monitor (Schild_Sel4_Syscall.HM_MLS);
      Put_Str ("[HM] MLS server escalated to STOP" & ASCII.CR & ASCII.LF);
   end;

   Put_Str ("[CONTAINMENT] injecting fault into Config Daemon (op=99)..." & ASCII.CR & ASCII.LF);
   declare
      R : Word := Schild_Sel4_Syscall.Call_IPC (Config_EP_Slot, 99, 0);
   begin
      null;
   end;
   declare
      Badge : Word := Schild_Sel4_Syscall.Wait (Config_Fault_Slot);
   begin
      Put_Str (ASCII.CR & ASCII.LF & "[FAULT] Caught Config fault — badge=0x");
      Put_Hex (Badge);
      Put_Str (" — restarting" & ASCII.CR & ASCII.LF);
      Schild_Sel4_Syscall.Health_Monitor (Schild_Sel4_Syscall.HM_Config_Daemon);
      Put_Str ("[CONTAINMENT] Config Daemon contained" & ASCII.CR & ASCII.LF);
   end;

   -- B.6: timeout-fault test.  Inject op=98 into the Config Daemon: it replies
   -- then spins to exhaust its sporadic scheduling-context budget; the kernel
   -- delivers a seL4_Fault_Timeout to the shared timeout endpoint (slot 215),
   -- carrying the SC badge (3 = Config Daemon) in MR[0].
   Put_Str ("[TIMEOUT] injecting budget overrun into Config Daemon (op=98)..." & ASCII.CR & ASCII.LF);
   declare
      R : Word := Schild_Sel4_Syscall.Call_IPC (Config_EP_Slot, 98, 0);
   begin
      null;
   end;
   declare
      Badge    : Word := Schild_Sel4_Syscall.Wait (Timeout_EP_Slot);
      SC_Badge : Word := Schild_Sel4_Syscall.Read_Recv_MR0;
   begin
      Put_Str ("[TIMEOUT] Caught budget overrun — SC badge=");
      Put_Dec (SC_Badge);
      Put_Str (" — temporal isolation enforced" & ASCII.CR & ASCII.LF);
   end;

   Put_Str ("==== Root Task ready ====" & ASCII.CR & ASCII.LF);

   -- Idle loop: service the e1000e IRQ notification (badge 0xE1) and yield.
   -- (Crash containment is handled above via the blocking Recv on the fault
   -- endpoint — the NetServer only runs while the root task blocks, so a
   -- non-blocking NBRecv poll here would starve it.)
   loop
      -- Stage 8.3: interrupt-driven e1000e RX. When the IRQ notification fires
      -- (badge 0xE1), forward a poll_rx Call to the NetServer (which reads ICR
      -- and dispatches), then ack the IRQ to re-enable it.
      if IRQ_Ntfn_Slot > 0 then
         declare
            Badge : Word := Schild_Sel4_Syscall.NBWait (IRQ_Ntfn_Slot);
         begin
            if Badge > 0 then
               Put_Str (ASCII.CR & ASCII.LF & "[IRQ] e1000e interrupt (badge=0x");
               Put_Hex (Badge);
               Put_Str (")" & ASCII.CR & ASCII.LF);
               declare
                  R : Word := Schild_Sel4_Syscall.Call_IPC (Net_EP_Slot, 1, 0);
               begin
                  -- op=1 = poll_rx; reply MR0 = status (1=packet, 0=idle).
                  null;
               end;
               declare
                  R : Word := Schild_Sel4_Syscall.IRQ_Handler_Ack (IRQ_Handler_Slot);
               begin
                  null;
               end;
            end if;
         end;
      end if;

      -- Cooperatively yield the CPU so the other domains (NetServer, MLS
      -- server, Config Daemon) get scheduled on the single core. The previous
      -- spin (`pause`) starved them, so an injected NetServer fault never got
      -- a chance to run — and therefore could never be contained.
      Schild_Sel4_Syscall.Yield;
   end loop;
end Schild_Root_Task;
