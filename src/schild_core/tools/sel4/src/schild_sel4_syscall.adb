-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- =============================================================================
-- Schild TCB — seL4 syscall thin bindings (body — Stage 6 fault handling)
-- =============================================================================

with Schild_Sel4_BootInfo; use Schild_Sel4_BootInfo;
with Schild_HM_Model;      use type Schild_HM_Model.HM_Action;
with Schild_Launch_Model;

package body Schild_Sel4_Syscall
  with SPARK_Mode => Off
is
   procedure Put_String (S : String) is
   begin
      for I in S'Range loop
         Debug_Put_Char (Unsigned_32 (Character'Pos (S (I))));
      end loop;
   end Put_String;

   procedure Fault_Guard is
   begin
      --  Containment, not recovery: the fault message has already been consumed
      --  by the idle loop's NBRecv, and the faulted thread remains suspended on
      --  its fault notification while the root task keeps running. Full thread
      --  restart (TCBWriteRegisters + Resume) is the next step.
      null;
   end Fault_Guard;

   type BI_Access is access all BootInfo;
   function Get_BootInfo return BI_Access
     with Import, Convention => C, External_Name => "schild_get_bootinfo";

   CNode_Slot : constant Cap_Ref := 2;

   -- seL4 object types (MCS `api_object` enum).  SchedContext/Reply are MCS-only;
   -- the arch types (PDPT/PML4/Frame/PT/PD) are shifted +2 relative to non-MCS.
   Object_TCB           : constant Word := 1;
   Object_Endpoint      : constant Word := 2;
   Object_Notification  : constant Word := 3;
   Object_CNode         : constant Word := 4;
   Object_SchedContext  : constant Word := 5;   -- MCS
   Object_Reply         : constant Word := 6;   -- MCS
   Object_PDPT          : constant Word := 7;
   Object_PML4          : constant Word := 8;
   Object_Frame         : constant Word := 10;  -- 4K frame (9 = huge page)
   Object_LargePage     : constant Word := 11;  -- 2 MiB large page (seL4_X86_LargePageObject)
   Object_PageTable     : constant Word := 12;
   Object_PageDirectory : constant Word := 13;

   -- Health Monitoring: per-domain restart state (populated at launch).
   Net_TCB_Cap : Cap_Ref := 0;
   Net_Entry    : Word := 0;
   Net_Stack    : Word := 0;
   MLS_TCB_Cap : Cap_Ref := 0;
   MLS_Entry    : Word := 0;
   MLS_Stack    : Word := 0;
   Cfg_TCB_Cap : Cap_Ref := 0;
   Cfg_Entry    : Word := 0;
   Cfg_Stack    : Word := 0;

   -- ARINC 653 Health Monitoring: 3-level fault model.  The escalation
   -- decision logic (process RESTART -> partition STOP -> module IDLE) is
   -- factored into Schild_HM_Model (SPARK Level 4); only the mechanism
   -- (TCBWriteRegisters + TCBResume) remains here.
   HM_St : Schild_HM_Model.HM_State;

   -- Root-task orchestration launch model: tracks "launched exactly once" and
   -- fault/timeout endpoint assignment (SPARK Level 4, see Schild_Launch_Model).
   Launch_St : Schild_Launch_Model.Launch_State;

   procedure Health_Monitor (Domain : HM_Domain) is
      TCB : Cap_Ref := 0;
      Ent : Word := 0;
      Stk : Word := 0;
      M   : Schild_HM_Model.HM_Domain;
      Act : Schild_HM_Model.HM_Action;
   begin
      Put_String ("[HM] ");
      case Domain is
         when HM_NetServer =>
            TCB := Net_TCB_Cap; Ent := Net_Entry; Stk := Net_Stack;
            M := Schild_HM_Model.HM_NetServer;
            Put_String ("NetServer");
         when HM_MLS =>
            TCB := MLS_TCB_Cap; Ent := MLS_Entry; Stk := MLS_Stack;
            M := Schild_HM_Model.HM_MLS;
            Put_String ("MLS server");
         when HM_Config_Daemon =>
            TCB := Cfg_TCB_Cap; Ent := Cfg_Entry; Stk := Cfg_Stack;
            M := Schild_HM_Model.HM_Config_Daemon;
            Put_String ("Config Daemon");
      end case;

      -- Escalation decision is delegated to the SPARK-proved state machine.
      Schild_HM_Model.Evaluate (HM_St, M, Act);

      case Act is
         when Schild_HM_Model.Restart =>
            -- process-level: RESTART.
            Put_String (" fault -> RESTART (process level)" & ASCII.CR & ASCII.LF);
            if TCB /= 0 then
               declare
                  R : Word := TCB_Write_Registers (TCB, Ent, Stk);
               begin
                  Put_String ("[HM]   TCBWriteRegisters="); Put_Hex (R);
                  Put_String (ASCII.CR & ASCII.LF);
               end;
               declare
                  R : Word := TCB_Resume (TCB);
               begin
                  Put_String ("[HM]   TCBResume="); Put_Hex (R);
                  Put_String (ASCII.CR & ASCII.LF);
               end;
            end if;
         when Schild_HM_Model.Stop |
              Schild_HM_Model.Module_Idle =>
            -- partition-level: STOP (leave suspended, do not restart).
            Put_String (" fault -> STOP (partition level, repeated fault)"
                        & ASCII.CR & ASCII.LF);
            -- module-level: every domain escalated -> module idle.
            if Act = Schild_HM_Model.Module_Idle then
               Put_String ("[HM] MODULE IDLE (all partitions stopped)"
                           & ASCII.CR & ASCII.LF);
            end if;
      end case;
   end Health_Monitor;

   -- =========================================================================
   -- ARINC 653 partition -> MCS scheduling-context budget mapping.
   --
   -- Each seL4 domain (a "partition") gets its own scheduling context with a
   -- distinct CPU budget, so a runaway server is pre-empted after its timeslice
   -- (budget == period, round-robin) or blocked until the next period
   -- (budget < period, sporadic — used by the B.6 timeout path).
   -- =========================================================================
   NetServer_Budget_Us : constant Word := 5_000;  -- network: largest slice
   NetServer_Period_Us : constant Word := 5_000;  -- round-robin
   MLS_Budget_Us       : constant Word := 2_000;  -- security decisions
   MLS_Period_Us       : constant Word := 2_000;  -- round-robin
   Config_Budget_Us    : constant Word := 1_000;  -- config: smallest slice
   Config_Period_Us    : constant Word := 100_000;  -- sporadic (1% CPU) -> B.6 timeout

   -- Shared timeout-fault endpoint (B.6): each domain's TCB points here; when a
   -- sporadic budget is exhausted the kernel delivers a seL4_Fault_Timeout
   -- carrying the SC badge (identifies the domain).  The slot itself is
   -- Timeout_EP_Slot from the package specification's slot map.

   -- SC badges delivered in a timeout fault's MR[0] to name the domain.
   NetServer_SC_Badge : constant Word := 1;
   MLS_SC_Badge       : constant Word := 2;
   Config_SC_Badge    : constant Word := 3;

   -- MCS: create + configure a scheduling context and a reply object for a new
   -- thread, then bind the SC to the TCB.  Budget/period are in microseconds;
   -- budget == period yields round-robin, budget < period yields a sporadic
   -- server (hard bound).  Returns 0 on success, or a non-zero stage code
   -- (1=SC retype, 2=reply retype, 3=ConfigureFlags, 4=Bind).
   function Setup_MCS_Thread
     (SchedControl : Cap_Ref;
      UT_SC        : Cap_Ref;
      UT_Reply     : Cap_Ref;
      SC_Slot      : Cap_Ref;
      Reply_Slot   : Cap_Ref;
      TCB_Slot     : Cap_Ref;
      Budget_Us    : Word;
      Period_Us    : Word;
      SC_Badge     : Word) return Word
   is
      R : Word;
   begin
      Put_String ("[MCS] SC@"); Put_Dec (SC_Slot);
      Put_String (" + Reply@"); Put_Dec (Reply_Slot);
      Put_String (" -> TCB@"); Put_Dec (TCB_Slot);
      Put_String (" budget="); Put_Dec (Budget_Us);
      Put_String (" period="); Put_Dec (Period_Us);
      Put_String (" badge="); Put_Dec (SC_Badge);
      Put_String ("..." & ASCII.CR & ASCII.LF);

      R := Retype_Object (UT_SC, Object_SchedContext, 7, CNode_Slot, 0, SC_Slot, 1);
      if R /= 0 then return 1; end if;

      R := Retype_Object (UT_Reply, Object_Reply, 0, CNode_Slot, 0, Reply_Slot, 1);
      if R /= 0 then return 2; end if;

      R := SchedControl_ConfigureFlags (SchedControl, SC_Slot,
                                        Budget_Us, Period_Us, 0, SC_Badge, 0);
      if R /= 0 then return 3; end if;

      R := SchedContext_Bind (SC_Slot, TCB_Slot);
      if R /= 0 then return 4; end if;

      -- Timeout endpoint: a budget overrun (sporadic) delivers a timeout fault
      -- here, letting the root task trigger Health Monitoring (B.6).
      R := TCB_Set_Timeout_Endpoint (TCB_Slot, Timeout_EP_Slot);
      if R /= 0 then return 5; end if;

      return 0;
   end Setup_MCS_Thread;

   -- ─── Stage 6: Fault Handler Initialization ───

   function Init_Fault_Handler return Word is
      -- Access BootInfo to find untyped memory
      BI : constant BI_Access := Get_BootInfo;

      -- seL4 standard slot assignments
      CNode_Slot          : constant Cap_Ref := 2;   -- seL4_CapInitThreadCNode
      -- The seL4 fault handler MUST be an ENDPOINT (not a notification):
      -- non-MCS sendFaultIPC() rejects a notification fault handler as a
      -- CapFault ("cap fault in send phase"). So we retype an endpoint here.
      Fault_EP_Slot       : constant Cap_Ref := Root_Fault_EP_Slot; -- our fault endpoint
      Min_Size_Bits       : constant Word := 20;     -- 1MB minimal (skip tiny RAM chunks)

   begin
      -- First: set schild_ipc_buf_addr via C (reads qword[4] from BI frame).
      -- This is CRITICAL — without it, set_mr/set_ec write to NULL+offset.
      declare
         function Get_BI_Frame return Word
           with Import, Convention => C, External_Name => "schild_get_bootinfo_frame";
         procedure Dump_Raw_BI (Frame : Word)
           with Import, Convention => C, External_Name => "schild_dump_raw_bootinfo";
      begin
         Dump_Raw_BI (Get_BI_Frame);
      end;

      -- IPC buffer is already set up by the kernel during boot.
      -- No TCBSetIPCBuffer needed — the kernel's create_initial_thread
      -- correctly installs the IPC buffer frame cap at tcbBuffer.
      Put_String ("[Stage6] IPC buffer: kernel-managed, skipping TCBSetIPCBuffer" & ASCII.CR & ASCII.LF);
      Put_String ("[Stage6] Scanning for untyped region..." & ASCII.CR & ASCII.LF);

      -- Find first usable untyped region. Skip [0 .. 8 MiB): the 0..1 MiB BIOS
      -- region and the 1..8 MiB boot-reuse region (the kernel's discarded boot
      -- code). On the T580 the 4 MiB boot-reuse chunk at 0x400000 hangs when
      -- the first Retype resets it (resetUntypedCap memzero), so all kernel
      -- objects are retyped from the freemem (>= 8 MiB) instead.
      for I in 1 .. N_UNTYPED loop
         if BI.all.Untyped_List (I).Size_Bits > 0
           and then Word (BI.all.Untyped_List (I).Size_Bits) >= Min_Size_Bits
           and then BI.all.Untyped_List (I).PAddr >= 16#800000#
             and then BI.all.Untyped_List (I).PAddr <  16#20000000#  -- skip null-phys region
           and then BI.all.Untyped_List (I).Is_Device = 0  -- RAM only (kernel object)
         then
            declare
               Slot_Base    : Cap_Ref := BI.all.Untyped_Start + Word (I - 1);
               Region_Bits  : Word   := Word (BI.all.Untyped_List (I).Size_Bits);
               Addr         : Word   := BI.all.Untyped_List (I).PAddr;
               Result       : Word;
            begin
               -- Slot must be within our CSpace
               if Slot_Base >= BI.all.Untyped_End then
                  Put_String ("[Stage6] WARN: untyped slot out of range, skip" & ASCII.CR & ASCII.LF);
               else
                  Put_String ("[Stage6] Retyping untyped at 0x");
                  Put_Hex (Addr);
                  Put_String (" (size bits=");
                  Put_Dec (Region_Bits);
                  Put_String (") -> Endpoint at slot ");
                  Put_Dec (Fault_EP_Slot);
                  Put_String (ASCII.CR & ASCII.LF);

                  Result := Retype_Object
                    (Untyped_Cap => Slot_Base,
                     Object_Type => Object_Endpoint,   -- seL4_EndpointObject (fault handler must be an endpoint)
                     Size_Bits   => 0,
                     Root_CNode  => CNode_Slot,
                     Node_Depth  => 0,   -- use root CNode directly
                     Dest_Slot   => Fault_EP_Slot,
                     Num_Objects => 1);
                  Put_String ("[Stage6] UntypedRetype -> raw=0x");
                  Put_Hex (Result);
                  Put_String (ASCII.CR & ASCII.LF);

                  -- B.6: shared timeout-fault endpoint (budget overrun -> HM).
                  Result := Retype_Object
                    (Untyped_Cap => Slot_Base,
                     Object_Type => Object_Endpoint,
                     Size_Bits   => 0,
                     Root_CNode  => CNode_Slot,
                     Node_Depth  => 0,
                     Dest_Slot   => Timeout_EP_Slot,
                     Num_Objects => 1);
                  Put_String ("[Stage6] Timeout endpoint @4115 -> raw=0x");
                  Put_Hex (Result);
                  Put_String (ASCII.CR & ASCII.LF);

                  -- Record the shared timeout-fault endpoint in the launch model
                  -- (must be bound before any domain launches).
                  Schild_Launch_Model.Bind_Timeout_EP
                    (Launch_St, Natural (Timeout_EP_Slot));

                  -- Stage 6.1: Bind notification as TCB fault handler
                  Put_String ("[Stage6] Binding fault handler (TCBSetSpace)..."
                              & ASCII.CR & ASCII.LF);
                  declare
                     TCB_Slot     : constant Cap_Ref := 1;   -- seL4_CapInitThreadTCB
                     VSpace_Slot  : constant Cap_Ref := 3;   -- seL4_CapInitThreadVSpace
                     Bind_Result  : Word;
                  begin
                     Bind_Result := TCB_Set_Fault_Handler
                       (TCB_Cap      => TCB_Slot,
                        Fault_EP     => Fault_EP_Slot,
                        CSpace_Root  => CNode_Slot,
                        CSpace_Data  => 0,
                        VSpace_Root  => VSpace_Slot,
                        VSpace_Data  => 0);
                     Put_String ("[Stage6] TCBSetSpace -> raw=0x");
                     Put_Hex (Bind_Result);
                     Put_String (ASCII.CR & ASCII.LF);
                  end;

                  Put_String ("[Stage6] Fault handler initialized — endpoint at slot "
                              & ASCII.CR & ASCII.LF);
                  return 0;
               end if;
            end;
         end if;
      end loop;

      Put_String ("[Stage6] ERROR: no suitable untyped region found!" & ASCII.CR & ASCII.LF);
      return 1;
   end Init_Fault_Handler;

    -- MLS address helpers (from C)
    function MLS_Entry_Addr return Word
      with Import, Convention => C, External_Name => "schild_mls_entry_addr";
    function MLS_Stack_Addr return Word
      with Import, Convention => C, External_Name => "schild_mls_stack_addr";

    -- Config Daemon address helpers (from C)
    function Config_Entry_Addr return Word
      with Import, Convention => C, External_Name => "schild_config_entry_addr";
    function Config_Stack_Addr return Word
      with Import, Convention => C, External_Name => "schild_config_stack_addr";

    function Launch_MLS_Server return Word is
       BI : constant BI_Access := Get_BootInfo;
       Min_Size_Bits : constant Word := 20;  -- 1MB (skip tiny RAM chunks)
       UT1, UT2, UT3, UT4, UT5, UT6 : Cap_Ref := 0;
       Found    : Natural := 0;
       VSpace_Slot : constant Cap_Ref := 3;
       EP_Slot     : constant Cap_Ref := MLS_EP_Slot;
       TCB_Slot    : constant Cap_Ref := MLS_TCB_Slot;
       Fault_Slot  : constant Cap_Ref := MLS_Fault_Slot;
       IPC_Frame_Slot : constant Cap_Ref := MLS_IPC_Frame_Slot;
       SC_Slot     : constant Cap_Ref := MLS_SC_Slot;   -- MCS scheduling context
       Reply_Slot  : constant Cap_Ref := MLS_Reply_Slot;   -- MCS reply object
       IPC_Buf_VAddr  : constant Word := 16#500000#;
       R : Word;
    begin
       -- UT1..UT4: all MUST be RAM (non-device) untyped — kernel objects (TCB,
       -- endpoint, notification) and the IPC buffer frame cannot be retyped
       -- from device memory (device-bypass removed, P0-2).
       for I in 1 .. N_UNTYPED loop
          exit when Found >= 6;
          if BI.all.Untyped_List (I).Size_Bits > 0
            and then Word (BI.all.Untyped_List (I).Size_Bits) >= Min_Size_Bits
            and then BI.all.Untyped_List (I).PAddr >= 16#800000#
             and then BI.all.Untyped_List (I).PAddr <  16#20000000#
            and then BI.all.Untyped_List (I).Is_Device = 0
          then
             if UT1 = 0 then
                UT1 := BI.all.Untyped_Start + Word (I - 1);
                Found := Found + 1;
             elsif UT2 = 0 then
                UT2 := BI.all.Untyped_Start + Word (I - 1);
                Found := Found + 1;
             elsif UT3 = 0 then
                UT3 := BI.all.Untyped_Start + Word (I - 1);
                Found := Found + 1;
             elsif UT4 = 0 then
                -- Dedicated IPC buffer frame (RAM).
                UT4 := BI.all.Untyped_Start + Word (I - 1);
                Found := Found + 1;
             elsif UT5 = 0 then
                -- MCS scheduling context (RAM).
                UT5 := BI.all.Untyped_Start + Word (I - 1);
                Found := Found + 1;
             elsif UT6 = 0 then
                -- MCS reply object (RAM).
                UT6 := BI.all.Untyped_Start + Word (I - 1);
                Found := Found + 1;
             end if;
          end if;
       end loop;

       if Found < 6 then
          Put_String ("[S7.7] FATAL: Need 6 RAM untyped, found ");
          Put_Dec (Word (Found));
          Put_String (ASCII.CR & ASCII.LF);
          return 1;
       end if;


       -- 1. Endpoint at slot MLS_EP_Slot (4096)
       Put_String ("[S7.7] Endpoint at 4096... ");
       R := Retype_Object (UT1, Object_Endpoint, 0, CNode_Slot, 0, EP_Slot, 1);
       Put_Hex (R); Put_String (ASCII.CR & ASCII.LF);

       -- 2. Fault endpoint at slot MLS_Fault_Slot (fault handler MUST be an endpoint)
       Put_String ("[S7.7] FaultEP at 4097... ");
       R := Retype_Object (UT2, Object_Endpoint, 0, CNode_Slot, 0, Fault_Slot, 1);
       Put_Hex (R); Put_String (ASCII.CR & ASCII.LF);

       -- 3. TCB at slot 200
       Put_String ("[S7.7] TCB at 4098... ");
       R := Retype_Object (UT3, Object_TCB, 0, CNode_Slot, 0, TCB_Slot, 1);
       Put_Hex (R); Put_String (ASCII.CR & ASCII.LF);

       -- 4. Dedicated 4K IPC buffer frame (RAM) at slot 202
       Put_String ("[S7.7] IPC frame at 4099... ");
       R := Retype_Object (UT4, Object_Frame, 0, CNode_Slot, 0, IPC_Frame_Slot, 1);
       Put_Hex (R); Put_String (ASCII.CR & ASCII.LF);

       -- 5. Map the frame into the (shared) VSpace at 0x500000
       Put_String ("[S7.7] PageMap 0x500000... ");
       R := Page_Map (IPC_Frame_Slot, VSpace_Slot, IPC_Buf_VAddr);
       Put_Hex (R); Put_String (ASCII.CR & ASCII.LF);

       -- 5.5 MCS: scheduling context + reply object, configure + bind.
       R := Setup_MCS_Thread (BI.all.SchedControl_Start, UT5, UT6,
                              SC_Slot, Reply_Slot, TCB_Slot,
                              MLS_Budget_Us, MLS_Period_Us, MLS_SC_Badge);
       Put_Hex (R); Put_String (ASCII.CR & ASCII.LF);

       -- 6. SetSpace (fault handler + cspace/vspace)
       Put_String ("[S7.7] SetSpace... ");
       R := TCB_Set_Fault_Handler (TCB_Slot, Fault_Slot,
                                    CNode_Slot, 0, VSpace_Slot, 0);
       Put_Hex (R); Put_String (ASCII.CR & ASCII.LF);

       -- 7. SetIPCBuffer: dedicate the 4K frame at 0x500000 to the MLS TCB
       Put_String ("[S7.7] SetIPCBuffer... ");
       R := TCB_Set_IPC_Buffer (TCB_Slot, IPC_Frame_Slot, IPC_Buf_VAddr);
       Put_Hex (R); Put_String (ASCII.CR & ASCII.LF);

       -- 8. Write registers (RIP + RSP)
       Put_String ("[S7.7] WriteRegs... ");
       R := TCB_Write_Registers (TCB_Slot, MLS_Entry_Addr, MLS_Stack_Addr);
       Put_Hex (R); Put_String (ASCII.CR & ASCII.LF);

       -- 9. Set endpoint CPtr + dedicated IPC buffer vaddr for MLS server
       declare
          procedure Set_MLS_EP (EP : Word)
            with Import, Convention => C, External_Name => "schild_set_mls_endpoint";
          procedure Set_MLS_IPC (Addr : Word)
            with Import, Convention => C, External_Name => "schild_set_mls_ipc_buf";
          procedure Set_MLS_Reply (Rpl : Word)
            with Import, Convention => C, External_Name => "schild_set_mls_reply";
       begin
          Set_MLS_EP (EP_Slot);
          Set_MLS_IPC (IPC_Buf_VAddr);  -- dedicated IPC buffer at 0x500000
          Set_MLS_Reply (Reply_Slot);   -- reply object CPtr for Recv/ReplyRecv
       end;

       -- 10. Resume MLS thread
       Put_String ("[S7.7] Resume... ");
       R := TCB_Resume (TCB_Slot);
       Put_Hex (R); Put_String (ASCII.CR & ASCII.LF);

       -- Health Monitoring: remember MLS TCB/entry/stack for restart.
       MLS_TCB_Cap := TCB_Slot;
       MLS_Entry    := MLS_Entry_Addr;
       MLS_Stack    := MLS_Stack_Addr;

       -- 11. Yield CPU to let MLS server start its Recv loop
       Yield;

       -- 12. IPC test: Call (send + wait for reply) — end-to-end IPC.
       --    MLS server receives op/level via MR registers, replies via MR[0].
       Put_String ("[S7.7] IPC Call... ");
       R := Call_IPC (EP_Slot, 2, 5);   -- op=2 (same-level), target_level=5
       Put_Hex (R); Put_String (ASCII.CR & ASCII.LF);
       Put_String ("[S7.7] Reply MR0 (result): ");
       Put_Hex (Read_IPC_MR0); Put_String (ASCII.CR & ASCII.LF);

       -- R3: exercise all three Bell-LaPadula ops via IPC (badge=0 => Public).
       R := Call_IPC (EP_Slot, 0, 0);   -- read-down: Public >= Public  -> 1
       Put_String ("[R3] MLS op=0 read-down reply (expect 1): ");
       Put_Hex (Read_IPC_MR0); Put_String (ASCII.CR & ASCII.LF);
       R := Call_IPC (EP_Slot, 1, 5);   -- write-up: Public <= Top_Secret -> 1
       Put_String ("[R3] MLS op=1 write-up reply (expect 1): ");
       Put_Hex (Read_IPC_MR0); Put_String (ASCII.CR & ASCII.LF);
       R := Call_IPC (EP_Slot, 2, 5);   -- equal: Public != Top_Secret   -> 0
       Put_String ("[R3] MLS op=2 equal reply (expect 0): ");
       Put_Hex (Read_IPC_MR0); Put_String (ASCII.CR & ASCII.LF);

       Put_String ("[S7.7] MLS Server launched successfully" & ASCII.CR & ASCII.LF);
       Schild_HM_Model.Launch (HM_St, Schild_HM_Model.HM_MLS);
       Schild_Launch_Model.Launch (Launch_St, Schild_Launch_Model.MLS, Natural (Fault_Slot));
       return 0;
    end Launch_MLS_Server;

    -- ==========================================================================
    -- R3: isolated Config Daemon process (own fault domain).
    --   Retype an endpoint @4119, fault endpoint @4120, TCB @4121 and a
    --   dedicated IPC buffer frame @4122 (mapped @0x52B000), then resume the
    --   config_daemon_main thread.  Returns 0 on success.
    -- ==========================================================================
    function Launch_Config_Daemon return Word is
       BI : constant BI_Access := Get_BootInfo;
       Min_Size_Bits : constant Word := 20;  -- 1MB (skip tiny RAM chunks)
       UT1, UT2, UT3, UT4, UT5, UT6 : Cap_Ref := 0;
       Found : Natural := 0;
       VSpace_Slot : constant Cap_Ref := 3;
       EP_Slot     : constant Cap_Ref := Config_EP_Slot;
       TCB_Slot    : constant Cap_Ref := Config_TCB_Slot;
       Fault_Slot  : constant Cap_Ref := Config_Fault_Slot;
       IPC_Frame_Slot : constant Cap_Ref := Config_IPC_Frame_Slot;
       SC_Slot     : constant Cap_Ref := Config_SC_Slot;
       Reply_Slot  : constant Cap_Ref := Config_Reply_Slot;
       IPC_Buf_VAddr  : constant Word := 16#52B000#;
       R : Word;
    begin
       for I in 1 .. N_UNTYPED loop
          exit when Found >= 6;
          if BI.all.Untyped_List (I).Size_Bits > 0
            and then Word (BI.all.Untyped_List (I).Size_Bits) >= Min_Size_Bits
            and then BI.all.Untyped_List (I).PAddr >= 16#800000#
            and then BI.all.Untyped_List (I).PAddr <  16#20000000#
            and then BI.all.Untyped_List (I).Is_Device = 0
          then
             if UT1 = 0 then
                UT1 := BI.all.Untyped_Start + Word (I - 1); Found := Found + 1;
             elsif UT2 = 0 then
                UT2 := BI.all.Untyped_Start + Word (I - 1); Found := Found + 1;
             elsif UT3 = 0 then
                UT3 := BI.all.Untyped_Start + Word (I - 1); Found := Found + 1;
             elsif UT4 = 0 then
                UT4 := BI.all.Untyped_Start + Word (I - 1); Found := Found + 1;
             elsif UT5 = 0 then
                UT5 := BI.all.Untyped_Start + Word (I - 1); Found := Found + 1;
             elsif UT6 = 0 then
                UT6 := BI.all.Untyped_Start + Word (I - 1); Found := Found + 1;
             end if;
          end if;
       end loop;
       if Found < 6 then
          Put_String ("[R3] FATAL: need 6 RAM untyped for Config Daemon" & ASCII.CR & ASCII.LF);
          return 1;
       end if;
       R := Retype_Object (UT1, Object_Endpoint, 0, CNode_Slot, 0, EP_Slot, 1);
       if R /= 0 then return 2; end if;
       R := Retype_Object (UT2, Object_Endpoint, 0, CNode_Slot, 0, Fault_Slot, 1);
       if R /= 0 then return 3; end if;
       R := Retype_Object (UT3, Object_TCB, 0, CNode_Slot, 0, TCB_Slot, 1);
       if R /= 0 then return 4; end if;
       R := Retype_Object (UT4, Object_Frame, 0, CNode_Slot, 0, IPC_Frame_Slot, 1);
       if R /= 0 then return 5; end if;
       R := Page_Map (IPC_Frame_Slot, VSpace_Slot, IPC_Buf_VAddr);
       if R /= 0 then return 6; end if;
       -- MCS: scheduling context + reply object, configure + bind.
       R := Setup_MCS_Thread (BI.all.SchedControl_Start, UT5, UT6,
                              SC_Slot, Reply_Slot, TCB_Slot,
                              Config_Budget_Us, Config_Period_Us, Config_SC_Badge);
       if R /= 0 then return 11; end if;
       R := TCB_Set_Fault_Handler (TCB_Slot, Fault_Slot,
                                   CNode_Slot, 0, VSpace_Slot, 0);
       if R /= 0 then return 7; end if;
       R := TCB_Set_IPC_Buffer (TCB_Slot, IPC_Frame_Slot, IPC_Buf_VAddr);
       if R /= 0 then return 8; end if;
       R := TCB_Write_Registers (TCB_Slot, Config_Entry_Addr, Config_Stack_Addr);
       if R /= 0 then return 9; end if;
       declare
          procedure Set_Config_EP (EP : Word)
            with Import, Convention => C, External_Name => "schild_set_config_endpoint";
          procedure Set_Config_Reply (Rpl : Word)
            with Import, Convention => C, External_Name => "schild_set_config_reply";
       begin
          Set_Config_EP (EP_Slot);
          Set_Config_Reply (Reply_Slot);
       end;
       R := TCB_Resume (TCB_Slot);
       if R /= 0 then return 10; end if;

       -- Health Monitoring: remember Config Daemon TCB/entry/stack for restart.
       Cfg_TCB_Cap := TCB_Slot;
       Cfg_Entry    := Config_Entry_Addr;
       Cfg_Stack    := Config_Stack_Addr;

       Yield;
       -- IPC test: validate at Top_Secret (level=4) -> expect reply 1.
       R := Call_IPC (EP_Slot, 0, 4);
       Put_String ("[R3] Config Daemon validate@Top_Secret reply (expect 1): ");
       Put_Hex (Read_IPC_MR0);
       Put_String (ASCII.CR & ASCII.LF);
       -- Deny path: validate at Public (level=0) -> expect reply 0.
       R := Call_IPC (EP_Slot, 0, 0);
       Put_String ("[R3] Config Daemon validate@Public reply (expect 0): ");
       Put_Hex (Read_IPC_MR0);
       Put_String (ASCII.CR & ASCII.LF);
       Put_String ("[R3] Config Daemon launched successfully" & ASCII.CR & ASCII.LF);
       Schild_HM_Model.Launch (HM_St, Schild_HM_Model.HM_Config_Daemon);
       Schild_Launch_Model.Launch
         (Launch_St, Schild_Launch_Model.Config_Daemon, Natural (Fault_Slot));
       return 0;
    end Launch_Config_Daemon;

   -- ==========================================================================
   -- W2: real NIC discovery (ECAM + MSI) for the seL4 NetServer.
   --
   -- The root task maps a 2 MiB large frame covering the ECAM (MMCONFIG) window
   -- (0xF0000000, buses 0..1) into its own VSpace, scans bus 0 config space for
   -- the e1000/e1000e NIC, reads BAR0 and programs MSI.  On QEMU (no ECAM) it
   -- falls back to the hardcoded 82540EM (0xFEB00000), preserving the test path.
   -- ==========================================================================
   Nic_BAR0    : Word := 0;
   Nic_Bus     : Word := 0;
   Nic_Dev     : Word := 0;
   Nic_Func    : Word := 0;
   Nic_Is_Real : Boolean := False;

   -- W7: NVMe storage discovery (ECAM) for the seL4 NetServer.
   Nvme_BAR0   : Word := 0;

   Ecam_VAddr : constant Word := 16#0080_0000#;  -- root-VSpace vaddr (8 MiB, 2 MiB aligned)

   function MMIO_Read32 (Addr : Word) return Word
     with Import, Convention => C, External_Name => "schild_mmio_read32";
   procedure MMIO_Write32 (Addr, Val : Word)
     with Import, Convention => C, External_Name => "schild_mmio_write32";

   function Ecam_Read (Bus, Dev, Func, Off : Word) return Word is
      A : constant Word := Ecam_VAddr
        + Bus * 16#10_0000# + Dev * 16#8000# + Func * 16#1000# + Off;
   begin
      return MMIO_Read32 (A);
   end Ecam_Read;

   procedure Ecam_Write (Bus, Dev, Func, Off, Val : Word) is
      A : constant Word := Ecam_VAddr
        + Bus * 16#10_0000# + Dev * 16#8000# + Func * 16#1000# + Off;
   begin
      MMIO_Write32 (A, Val);
   end Ecam_Write;

   -- Program the MSI capability so the device delivers interrupts as a memory
   -- write to the LAPIC (0xFEE00000) at `Vector`.  Returns True on success.
   function Program_MSI (Bus, Dev, Func, Vector : Word) return Boolean is
      Cap_Off : Word := Ecam_Read (Bus, Dev, Func, 16#34#) and 16#FF#;
      Hdr     : Word;
   begin
      for I in 1 .. 16 loop
         exit when Cap_Off = 0 or Cap_Off > 16#FC#;
         Hdr := Ecam_Read (Bus, Dev, Func, Cap_Off);
         if (Hdr and 16#FF#) = 16#05# then
            declare
               Ctl : constant Word := Shift_Right (Hdr, 16) and 16#FFFF#;
            begin
               if (Ctl and 16#0080#) /= 0 then
                  Ecam_Write (Bus, Dev, Func, Cap_Off + 4, 16#FEE0_0000#);
                  Ecam_Write (Bus, Dev, Func, Cap_Off + 8, 0);
                  Ecam_Write (Bus, Dev, Func, Cap_Off + 12, Vector);
               else
                  Ecam_Write (Bus, Dev, Func, Cap_Off + 4, 16#FEE0_0000#);
                  Ecam_Write (Bus, Dev, Func, Cap_Off + 8, Vector);
               end if;
               Ecam_Write (Bus, Dev, Func, Cap_Off, Hdr or 16#0001_0000#);
               return True;
            end;
         end if;
         Cap_Off := Shift_Right (Hdr, 8) and 16#FF#;
      end loop;
      return False;
   end Program_MSI;

   -- Map the ECAM window (2 MiB large frame @ 0xF0000000) into the root VSpace.
   function Map_Ecam return Word is
      BI          : constant BI_Access := Get_BootInfo;
      Ecam_Phys   : constant Word := 16#F000_0000#;
      Root_VSpace : constant Cap_Ref := 3;
      Dev_UT      : Cap_Ref := 0;
      R           : Word;
   begin
      for I in 1 .. N_UNTYPED loop
         if BI.all.Untyped_List (I).Size_Bits > 0
           and then BI.all.Untyped_List (I).Is_Device = 1
           and then BI.all.Untyped_List (I).Size_Bits < 64
         then
            declare
               P  : constant Word := BI.all.Untyped_List (I).PAddr;
               Sz : constant Word := Shift_Left (Word (1), Natural (BI.all.Untyped_List (I).Size_Bits));
            begin
               if P <= Ecam_Phys and then Ecam_Phys < P + Sz then
                  Dev_UT := BI.all.Untyped_Start + Word (I - 1);
                  exit;
               end if;
            end;
         end if;
      end loop;
      if Dev_UT = 0 then
         Put_String ("[W2] no device-untyped for ECAM" & ASCII.CR & ASCII.LF);
         return 1;
      end if;

      R := Retype_Object (Dev_UT, Object_LargePage, 21, CNode_Slot, 0, Ecam_Frame_Slot, 1);
      if R /= 0 then
         Put_String ("[W2] ECAM retype FAIL "); Put_Hex (R); Put_String (ASCII.CR & ASCII.LF);
         return 2;
      end if;

      R := Page_Map (Ecam_Frame_Slot, Root_VSpace, Ecam_VAddr);
      if R /= 0 then
         Put_String ("[W2] ECAM map FAIL "); Put_Hex (R); Put_String (ASCII.CR & ASCII.LF);
         return 3;
      end if;

      Put_String ("[W2] ECAM window mapped @0x"); Put_Hex (Ecam_VAddr);
      Put_String (ASCII.CR & ASCII.LF);
      return 0;
   end Map_Ecam;

   -- Discover the NIC via ECAM and populate Nic_*.  Returns 0 on success
   -- (falling back to the QEMU 82540EM if ECAM is unavailable or no NIC found).
   function Init_NetServer_NIC return Word is
      R : Word := Map_Ecam;
   begin
      if R /= 0 then
         Nic_BAR0 := 16#FEB0_0000#;
         Nic_Bus := 0; Nic_Dev := 3; Nic_Func := 0;
         Nic_Is_Real := False;
         Put_String ("[W2] ECAM unavailable; QEMU 82540EM @0xFEB00000" & ASCII.CR & ASCII.LF);
         return 0;
      end if;

      for Slot in Word range 0 .. 31 loop
         for Fn in Word range 0 .. 7 loop
            declare
               D   : constant Word := Ecam_Read (0, Slot, Fn, 0);
               Vid : constant Word := D and 16#FFFF#;
               Did : constant Word := Shift_Right (D, 16) and 16#FFFF#;
            begin
               if Vid = 16#FFFF# then
                  exit when Fn = 0;
               elsif Vid = 16#8086# and then (Did = 16#15D8# or Did = 16#10D3# or Did = 16#100E#) then
                  Nic_Bus := 0; Nic_Dev := Slot; Nic_Func := Fn;
                  Nic_BAR0 := Ecam_Read (0, Slot, Fn, 16#10#) and 16#FFFF_FFF0#;
                  Nic_Is_Real := True;
                  declare
                     Cmd : constant Word := Ecam_Read (0, Slot, Fn, 16#04#);
                  begin
                     Ecam_Write (0, Slot, Fn, 16#04#, Cmd or 16#0004#);
                  end;
                  Put_String ("[W2] NIC found 0x"); Put_Hex (Vid);
                  Put_String (":"); Put_Hex (Did);
                  Put_String (" BAR0=0x"); Put_Hex (Nic_BAR0);
                  Put_String (ASCII.CR & ASCII.LF);
                  return 0;
               end if;
            end;
         end loop;
      end loop;

      Nic_BAR0 := 16#FEB0_0000#;
      Nic_Bus := 0; Nic_Dev := 3; Nic_Func := 0;
      Nic_Is_Real := False;
      Put_String ("[W2] NIC not found; QEMU 82540EM @0xFEB00000" & ASCII.CR & ASCII.LF);
      return 0;
   end Init_NetServer_NIC;

   -- Discover the NVMe controller via ECAM and populate Nvme_BAR0.  The ECAM
   -- window is already mapped by Init_NetServer_NIC (do not re-map it).  On
   -- QEMU i440fx the ECAM reads return device-MMIO garbage (no MMCONFIG), so
   -- the scan finds nothing and we fall back to the fixed QEMU NVMe BAR0.
   function Init_NetServer_NVMe return Word is
   begin
      for Slot in Word range 0 .. 31 loop
         for Fn in Word range 0 .. 7 loop
            declare
               D   : constant Word := Ecam_Read (0, Slot, Fn, 0);
               Vid : constant Word := D and 16#FFFF#;
               Did : constant Word := Shift_Right (D, 16) and 16#FFFF#;
            begin
               if Vid = 16#FFFF# then
                  exit when Fn = 0;
               elsif (Vid = 16#144D# and then Did = 16#A808#)   -- Samsung SM981 (T580)
                 or else (Vid = 16#1B36# and then Did = 16#0010#)   -- QEMU NVMe
                 or else (Vid = 16#8086# and then Did = 16#5845#)   -- Intel NVMe
               then
                  Nvme_BAR0 := Ecam_Read (0, Slot, Fn, 16#10#) and 16#FFFF_FFF0#;
                  declare
                     Cmd : constant Word := Ecam_Read (0, Slot, Fn, 16#04#);
                  begin
                     Ecam_Write (0, Slot, Fn, 16#04#, Cmd or 16#0004#);
                  end;
                  Put_String ("[W7] NVMe found 0x"); Put_Hex (Vid);
                  Put_String (":"); Put_Hex (Did);
                  Put_String (" BAR0=0x"); Put_Hex (Nvme_BAR0);
                  Put_String (ASCII.CR & ASCII.LF);
                  return 0;
               end if;
            end;
         end loop;
      end loop;

      -- QEMU i440fx fallback (1b36:0010 @ 0xfebf0000, empirically determined).
      Nvme_BAR0 := 16#FEBF_0000#;
      Put_String ("[W7] NVMe not found via ECAM; QEMU fallback @0xFEBF0000" & ASCII.CR & ASCII.LF);
      return 0;
   end Init_NetServer_NVMe;

          function Map_NetServer_VSpace return Word is
      BI : constant BI_Access := Get_BootInfo;
      PML4_Slot    : constant Cap_Ref := Net_PML4_Slot;   -- VSpace root (PML4)
      PDPT_Slot    : constant Cap_Ref := Net_PDPT_Slot;
      PD_Slot      : constant Cap_Ref := Net_PD_Slot;   -- one PD covers 0..1GB (PDPT[0])
      PT_Lo_Slot   : constant Cap_Ref := Net_PT_Lo_Slot;   -- PT @ PD[2] (image 0x400000 + IPC 0x510000)
      PT_Mmio_Slot : constant Cap_Ref := Net_PT_Mmio_Slot;   -- PT @ PD[3] (MMIO 0x600000)
      ASID_Pool    : constant Cap_Ref := 6;     -- seL4_CapInitThreadASIDPool
      Net_BAR0     : Word := 16#FEB00000#;   -- set from Nic_BAR0 after W2 discovery
      Net_Pages    : constant := 32;
      MMIO_VAddr   : constant Word := 16#600000#;
      IPC_VAddr    : constant Word := 16#510000#;
      Frame_Base   : constant Cap_Ref := MMIO_Frame_Base;
      Fan_Out      : constant Word := 256;
      RAM_UT, Dev_UT : Cap_Ref := 0;
      UT_PAddr, UT_Size_Bits, Offset_Frames, Total_Frames, Created : Word := 0;
      Slot_Cur     : Cap_Ref := Frame_Base;
      Frame        : Cap_Ref;
      VAddr        : Word;
      I            : Word := 0;
      R            : Word := 0;
   begin
      -- W2: discover the real NIC (ECAM scan; falls back to QEMU 82540EM).
      declare
         R0 : constant Word := Init_NetServer_NIC;
      begin
         if R0 /= 0 then
            Put_String ("[W2] Init_NetServer_NIC FAIL" & ASCII.CR & ASCII.LF);
         end if;
      end;
      Net_BAR0 := Nic_BAR0;

      -- W7: discover the NVMe controller (optional; storage disabled if absent).
      R := Init_NetServer_NVMe;

      -- 1. RAM untyped (>= 32 KB: 5 objects + IPC frame).
      for Idx in 1 .. N_UNTYPED loop
         if BI.all.Untyped_List (Idx).Size_Bits >= 15
           and then BI.all.Untyped_List (Idx).Is_Device = 0
           and then BI.all.Untyped_List (Idx).PAddr >= 16#800000#
         then
            RAM_UT := BI.all.Untyped_Start + Word (Idx - 1);
            exit;
         end if;
      end loop;
      if RAM_UT = 0 then
         Put_String ("[S8.2] FATAL: no RAM untyped for VSpace" & ASCII.CR & ASCII.LF);
         return 1;
      end if;

      -- 2. Retype VSpace objects: PML4, PDPT, PD, PT_lo, PT_mmio.
      R := Retype_Object (RAM_UT, Object_PML4, 0, CNode_Slot, 0, PML4_Slot, 1);
      if R /= 0 then return 2; end if;
      R := Retype_Object (RAM_UT, Object_PDPT, 0, CNode_Slot, 0, PDPT_Slot, 1);
      if R /= 0 then return 2; end if;
      R := Retype_Object (RAM_UT, Object_PageDirectory, 0, CNode_Slot, 0, PD_Slot, 1);
      if R /= 0 then return 2; end if;
      R := Retype_Object (RAM_UT, Object_PageTable, 0, CNode_Slot, 0, PT_Lo_Slot, 1);
      if R /= 0 then return 2; end if;
      R := Retype_Object (RAM_UT, Object_PageTable, 0, CNode_Slot, 0, PT_Mmio_Slot, 1);
      if R /= 0 then return 2; end if;

      -- 3. Bind the PML4 to an ASID.
      R := ASID_Pool_Assign (ASID_Pool, PML4_Slot);
      if R /= 0 then
         Put_String ("[S8.2] ASID assign FAIL"); Put_Hex (R);
         Put_String (ASCII.CR & ASCII.LF);
         return 2;
      end if;

      -- 4. Map PDPT -> PML4[0], PD -> PDPT[0], PTs -> PD[2]/PD[3].
      R := PDPT_Map (PDPT_Slot, PML4_Slot, 0);
      if R /= 0 then Put_String ("[S8.2] PDPTMap FAIL"); Put_Hex (R); Put_String (ASCII.CR & ASCII.LF); return 2; end if;
      R := Page_Directory_Map (PD_Slot, PML4_Slot, 0);
      if R /= 0 then Put_String ("[S8.2] PDMap FAIL"); Put_Hex (R); Put_String (ASCII.CR & ASCII.LF); return 2; end if;
      R := Page_Table_Map (PT_Lo_Slot, PML4_Slot, 16#400000#);
      if R /= 0 then Put_String ("[S8.2] PTLoMap FAIL"); Put_Hex (R); Put_String (ASCII.CR & ASCII.LF); return 2; end if;
      R := Page_Table_Map (PT_Mmio_Slot, PML4_Slot, MMIO_VAddr);
      if R /= 0 then Put_String ("[S8.2] PTMmioMap FAIL"); Put_Hex (R); Put_String (ASCII.CR & ASCII.LF); return 2; end if;

      -- 5. Mint + map the user image frames (shared with the Root Task).
      Frame := BI.all.User_Image_Frames_Start;
      VAddr := 16#400000#;
      I := 0;
      while Frame < BI.all.User_Image_Frames_End loop
         R := CNode_Mint (CNode_Slot, Image_Frame_Base + I, 64,
                          CNode_Slot, Frame, 64, 16#F#, 0);
         if R /= 0 then Put_String ("[S8.2] ImgMint FAIL"); Put_Hex (R); Put_String (ASCII.CR & ASCII.LF); return 2; end if;
         R := Page_Map (Image_Frame_Base + I, PML4_Slot, VAddr);
         if R /= 0 then Put_String ("[S8.2] ImgMap FAIL"); Put_Hex (R); Put_String (ASCII.CR & ASCII.LF); return 2; end if;
         Frame := Frame + 1;
         VAddr := VAddr + 16#1000#;
         I := I + 1;
      end loop;

      -- 6. Retype + map the NetServer IPC buffer frame (slot Net_IPC_Slot = 4104, vaddr 0x510000).
      R := Retype_Object (RAM_UT, Object_Frame, 0, CNode_Slot, 0, Net_IPC_Slot, 1);
      if R /= 0 then Put_String ("[S8.2] IpcRetype FAIL"); Put_Hex (R); Put_String (ASCII.CR & ASCII.LF); return 2; end if;
      R := Page_Map (Net_IPC_Slot, PML4_Slot, IPC_VAddr);
      if R /= 0 then Put_String ("[S8.2] IpcMap FAIL"); Put_Hex (R); Put_String (ASCII.CR & ASCII.LF); return 2; end if;

      -- 7. Locate the device-untyped for BAR0, retype + map the MMIO frames.
      for Idx in 1 .. N_UNTYPED loop
         if BI.all.Untyped_List (Idx).Size_Bits > 0
           and then BI.all.Untyped_List (Idx).Is_Device = 1
         then
            UT_PAddr     := BI.all.Untyped_List (Idx).PAddr;
            UT_Size_Bits := Word (BI.all.Untyped_List (Idx).Size_Bits);
            if UT_Size_Bits < 64 then
               declare
                  Sz : constant Word := Shift_Left (Word (1), Natural (UT_Size_Bits));
               begin
                  if UT_PAddr <= Net_BAR0 and then Net_BAR0 < UT_PAddr + Sz then
                     Dev_UT := BI.all.Untyped_Start + Word (Idx - 1);
                     exit;
                  end if;
               end;
            end if;
         end if;
      end loop;
      if Dev_UT = 0 then
         Put_String ("[S8.2] FATAL: no device-untyped for BAR0" & ASCII.CR & ASCII.LF);
         return 1;
      end if;
      Offset_Frames := (Net_BAR0 - UT_PAddr) / 16#1000#;
      Total_Frames  := Offset_Frames + Word (Net_Pages);
      while Created < Total_Frames loop
         declare
            Chunk : constant Word := Word'Min (Fan_Out, Total_Frames - Created);
         begin
            R := Retype_Object (Dev_UT, Object_Frame, 12, CNode_Slot, 0, Slot_Cur, Chunk);
            if R /= 0 then Put_String ("[S8.2] MMIO retype FAIL"); Put_Hex (R); Put_String (ASCII.CR & ASCII.LF); return 2; end if;
            Created  := Created + Chunk;
            Slot_Cur := Slot_Cur + Chunk;
         end;
      end loop;
      for J in 0 .. Net_Pages - 1 loop
         R := Page_Map (Frame_Base + Offset_Frames + Word (J), PML4_Slot,
                        MMIO_VAddr + Word (J) * 16#1000#);
         if R /= 0 then Put_String ("[S8.2] MMIO map FAIL"); Put_Hex (R); Put_String (ASCII.CR & ASCII.LF); return 2; end if;
      end loop;

      -- 8. W7: map the NVMe BAR0 (if discovered) into the NetServer VSpace.
      --     On QEMU i440fx (no ECAM) Nvme_BAR0 = 0 and this is skipped; on the
      --     T580 the NVMe lives in its own device-untyped region (like the NIC).
      if Nvme_BAR0 > 0 then
         declare
            Nvme_Dev_UT  : Cap_Ref := 0;
            Nvme_Offset  : Word := 0;
            Nvme_Pages   : constant Word := 8;          -- 32 KB (BAR0 is 8 KB)
            Nvme_VAddr   : constant Word := 16#620000#; -- next page after the NIC 32-page window
            Nvme_Created : Word := 0;
            Nvme_Slot    : Cap_Ref := Slot_Cur;         -- continue after the NIC frames
            procedure Nvme_Set_Mmio (Base : Word)
              with Import, Convention => C, External_Name => "schild_nvme_set_mmio";
         begin
            -- Case A: the NVMe shares the NIC's device-untyped (QEMU i440fx:
            -- both in the PCI MMIO window).  The NIC retype left a remaining
            -- untyped in Dev_UT starting at UT_PAddr + Total_Frames*0x1000.
            declare
               Rem_Start : constant Word := UT_PAddr + Total_Frames * 16#1000#;
               Rem_End   : constant Word := UT_PAddr + Shift_Left (Word (1), Natural (UT_Size_Bits));
            begin
               if Nvme_BAR0 >= Rem_Start and then Nvme_BAR0 < Rem_End then
                  Nvme_Dev_UT := Dev_UT;
                  Nvme_Offset := (Nvme_BAR0 - Rem_Start) / 16#1000#;
               end if;
            end;

            -- Case B: a separate device-untyped (T580: NIC and NVMe in distinct
            -- PCI windows).
            if Nvme_Dev_UT = 0 then
               for Idx in 1 .. N_UNTYPED loop
                  if BI.all.Untyped_List (Idx).Size_Bits > 0
                    and then BI.all.Untyped_List (Idx).Is_Device = 1
                  then
                     declare
                        NP : constant Word := BI.all.Untyped_List (Idx).PAddr;
                        NB : constant Word := Word (BI.all.Untyped_List (Idx).Size_Bits);
                     begin
                        if NB < 64 then
                           declare
                              Sz : constant Word := Shift_Left (Word (1), Natural (NB));
                           begin
                              if NP <= Nvme_BAR0 and then Nvme_BAR0 < NP + Sz then
                                 Nvme_Dev_UT := BI.all.Untyped_Start + Word (Idx - 1);
                                 Nvme_Offset := (Nvme_BAR0 - NP) / 16#1000#;
                                 exit;
                              end if;
                           end;
                        end if;
                     end;
                  end if;
               end loop;
            end if;

            if Nvme_Dev_UT = 0 then
               Put_String ("[W7] NVMe: no device-untyped for BAR0 (skip)" & ASCII.CR & ASCII.LF);
            else
               while Nvme_Created < Nvme_Offset + Nvme_Pages loop
                  declare
                     Chunk : constant Word := Word'Min (Fan_Out, Nvme_Offset + Nvme_Pages - Nvme_Created);
                  begin
                     R := Retype_Object (Nvme_Dev_UT, Object_Frame, 12, CNode_Slot, 0, Nvme_Slot, Chunk);
                     if R /= 0 then
                        Put_String ("[W7] NVMe retype FAIL"); Put_Hex (R); Put_String (ASCII.CR & ASCII.LF);
                        exit;
                     end if;
                     Nvme_Created := Nvme_Created + Chunk;
                     Nvme_Slot    := Nvme_Slot + Chunk;
                  end;
               end loop;

               if Nvme_Created >= Nvme_Offset + Nvme_Pages then
                  declare
                     Nvme_Base : constant Cap_Ref := Slot_Cur;  -- first NVMe frame slot
                  begin
                     for J in 0 .. Nvme_Pages - 1 loop
                        R := Page_Map (Nvme_Base + Nvme_Offset + Word (J), PML4_Slot,
                                       Nvme_VAddr + Word (J) * 16#1000#);
                        if R /= 0 then
                           Put_String ("[W7] NVMe map FAIL"); Put_Hex (R); Put_String (ASCII.CR & ASCII.LF);
                           exit;
                        end if;
                     end loop;
                     Slot_Cur := Nvme_Slot;   -- advance past the NVMe frames
                     Nvme_Set_Mmio (Nvme_VAddr);  -- tell the NetServer the MMIO base
                     Put_String ("[W7] NVMe BAR0 mapped @0x"); Put_Hex (Nvme_VAddr);
                     Put_String (ASCII.CR & ASCII.LF);
                  end;
               end if;
            end if;
         end;
      end if;

      Put_String ("[S8.2] NetServer VSpace ready (image+IPC+MMIO)" & ASCII.CR & ASCII.LF);
      return 0;
   end Map_NetServer_VSpace;





    function Init_NetServer_DMA return Word is
       BI : constant BI_Access := Get_BootInfo;
       Phys_Base : Word;
       R : Word;
    begin
       if BI.all.User_Image_Frames_End <= BI.all.User_Image_Frames_Start then
          Put_String ("[S8.1C] FATAL: no user image frames in BootInfo" & ASCII.CR & ASCII.LF);
          return 1;
       end if;
       -- The first image frame maps virtual 0x400000; its physical base gives
       -- the virtual->physical offset used by schild_dma_phys for DMA.
       R := Page_Get_Address (BI.all.User_Image_Frames_Start);
       if R >= 16#1000# then
          Put_String ("[S8.1C] PageGetAddress FAIL -> 0x");
          Put_Hex (R); Put_String (ASCII.CR & ASCII.LF);
          return 2;
       end if;
       Phys_Base := Read_IPC_MR0;
       Set_DMA_Offset (Phys_Base - 16#400000#);
       Put_String ("[S8.1C] image phys base 0x");
       Put_Hex (Phys_Base);
       Put_String ("  DMA offset 0x");
       Put_Hex (Phys_Base - 16#400000#);
       Put_String (ASCII.CR & ASCII.LF);
       return 0;
    end Init_NetServer_DMA;

    function Launch_NetServer return Word is
       BI : constant BI_Access := Get_BootInfo;
       Min_Size_Bits : constant Word := 20;  -- 1MB (skip tiny RAM chunks)
       UT1, UT3, UT4, UT5, UT6, UT7 : Cap_Ref := 0;
       Found    : Natural := 0;
       VSpace_Slot : constant Cap_Ref := Net_PML4_Slot;  -- NetServer VSpace (PML4)
       CNode_Slot  : constant Cap_Ref := 2;
       Net_IPC_VAddr : constant Word := 16#510000#;
       Fault_Slot  : constant Cap_Ref := Root_Fault_EP_Slot;  -- fault endpoint (root CSpace)
       -- MCS: scheduling context + reply object (root CSpace) + badged fault
       -- copy (root CSpace; MCS SetSpace resolves fault_ep in the CALLER's
       -- CSpace and copies it into the TCB).  The remaining slot constants
       -- (Net_EP_Slot, Net_TCB_Slot, Net_IPC_Slot, Net_SC_Slot, Net_Reply_Slot,
       -- Net_Fault_Root_Slot, Net_CSpace_Slot) come from the package spec.
       Net_CSpace_Bits : constant Word := 4;    -- 16 slots
       Root_CNode_Depth : constant Word := 64;  -- wordBits (guardSize 45 + radix 19)
       Net_EP_Cn    : constant Word := 1;       -- mint dest slot index (net_ep)
       Net_Reply_Cn : constant Word := 3;       -- mint dest slot index (reply)
       -- NetServer CSpace CPtrs: a retyped CNode has guardSize=0, so its slots
       -- are addressed from the top bits (slot N == CPtr N << 60).
       Net_EP_CPtr    : constant Word := 16#1000_0000_0000_0000#;  -- 1 << 60
       Net_Reply_CPtr : constant Word := 16#3000_0000_0000_0000#;  -- 3 << 60
       R : Word;

       function NetServer_Entry_Addr return Word
         with Import, Convention => C, External_Name => "schild_netserver_entry_addr";
       function NetServer_Stack_Addr return Word
         with Import, Convention => C, External_Name => "schild_netserver_stack_addr";
    begin
       -- Find untyped: UT1 (endpoint), UT3 (TCB), UT4 (IPC frame), UT5 (CNode).
       -- All MUST be RAM — kernel objects cannot be retyped from device memory.
       for I in 1 .. N_UNTYPED loop
          exit when Found >= 6;
          if BI.all.Untyped_List (I).Size_Bits > 0
            and then Word (BI.all.Untyped_List (I).Size_Bits) >= Min_Size_Bits
            and then BI.all.Untyped_List (I).PAddr >= 16#800000#
             and then BI.all.Untyped_List (I).PAddr <  16#20000000#
            and then BI.all.Untyped_List (I).Is_Device = 0
          then
             if UT1 = 0 then
                UT1 := BI.all.Untyped_Start + Word (I - 1);
                Found := Found + 1;
             elsif UT3 = 0 then
                UT3 := BI.all.Untyped_Start + Word (I - 1);
                Found := Found + 1;
             elsif UT4 = 0 then
                UT4 := BI.all.Untyped_Start + Word (I - 1);
                Found := Found + 1;
             elsif UT5 = 0 then
                UT5 := BI.all.Untyped_Start + Word (I - 1);
                Found := Found + 1;
             elsif UT6 = 0 then
                UT6 := BI.all.Untyped_Start + Word (I - 1);
                Found := Found + 1;
             elsif UT7 = 0 then
                UT7 := BI.all.Untyped_Start + Word (I - 1);
                Found := Found + 1;
             end if;
          end if;
       end loop;

       if Found < 6 then
          Put_String ("[S8.1D] FATAL: untyped exhausted" & ASCII.CR & ASCII.LF);
          return 1;
       end if;

       -- 1. net_ep endpoint at slot Net_EP_Slot (4102)
       Put_String ("[S8.1D] net_ep@4102... ");
       R := Retype_Object (UT1, Object_Endpoint, 0, CNode_Slot, 0, Net_EP_Slot, 1);
       Put_Hex (R); Put_String (ASCII.CR & ASCII.LF);
       if R /= 0 then return 2; end if;

       -- 2. NetServer TCB at slot 201
       Put_String ("[S8.1D] NetTCB@4103... ");
       R := Retype_Object (UT3, Object_TCB, 0, CNode_Slot, 0, Net_TCB_Slot, 1);
       Put_Hex (R); Put_String (ASCII.CR & ASCII.LF);
       if R /= 0 then return 2; end if;        -- 4.5. Create NetServer's own CSpace (CNode) and mint the minimal caps.
        Put_String ("[S8.1D] NetCNode@4105... ");
        R := Retype_Object (UT5, Object_CNode, Net_CSpace_Bits, CNode_Slot, 0, Net_CSpace_Slot, 1);
        Put_Hex (R); Put_String (ASCII.CR & ASCII.LF);
        if R /= 0 then return 2; end if;

        Put_String ("[S8.1D] Mint net_ep... ");
        R := CNode_Mint (Net_CSpace_Slot, Net_EP_Cn, Net_CSpace_Bits,
                         CNode_Slot, Net_EP_Slot, Root_CNode_Depth, 16#F#, 0);
        Put_Hex (R); Put_String (ASCII.CR & ASCII.LF);
        if R /= 0 then return 2; end if;

        -- MCS: mint a BADGED fault copy into the ROOT CSpace (slot Net_Fault_Root_Slot = 4113).  On MCS
        -- SetSpace resolves fault_ep in the CALLER's (root) CSpace and copies it
        -- into the TCB, so it must be a root-CSpace CPtr (not NetServer's).
        Put_String ("[S8.1D] Mint badged fault (root@4113)... ");
        R := CNode_Mint (CNode_Slot, Net_Fault_Root_Slot, Root_CNode_Depth,
                         CNode_Slot, Fault_Slot, Root_CNode_Depth, 16#F#, 16#E2#);
        Put_Hex (R); Put_String (ASCII.CR & ASCII.LF);
        if R /= 0 then return 2; end if;

        -- MCS: scheduling context + reply object, configure + bind.
        R := Setup_MCS_Thread (BI.all.SchedControl_Start, UT6, UT7,
                               Net_SC_Slot, Net_Reply_Slot, Net_TCB_Slot,
                               NetServer_Budget_Us, NetServer_Period_Us,
                               NetServer_SC_Badge);
        Put_Hex (R); Put_String (ASCII.CR & ASCII.LF);
        if R /= 0 then return 2; end if;

        Put_String ("[S8.1D] Mint reply into Net CSpace slot 3... ");
        R := CNode_Mint (Net_CSpace_Slot, Net_Reply_Cn, Net_CSpace_Bits,
                         CNode_Slot, Net_Reply_Slot, Root_CNode_Depth, 16#F#, 0);
        Put_Hex (R); Put_String (ASCII.CR & ASCII.LF);
        if R /= 0 then return 2; end if;

        -- 5. SetSpace (fault = badged root CPtr 4113, cspace=4105, vspace=4106).
       Put_String ("[S8.1D] SetSpace... ");
       R := TCB_Set_Fault_Handler (Net_TCB_Slot, Net_Fault_Root_Slot,
                                    Net_CSpace_Slot, 0, VSpace_Slot, 0);
       Put_Hex (R); Put_String (ASCII.CR & ASCII.LF);
       if R /= 0 then return 2; end if;

       -- 6. SetIPCBuffer
       Put_String ("[S8.1D] SetIPCBuffer... ");
       R := TCB_Set_IPC_Buffer (Net_TCB_Slot, Net_IPC_Slot, Net_IPC_VAddr);
       Put_Hex (R); Put_String (ASCII.CR & ASCII.LF);
       if R /= 0 then return 2; end if;

       -- 7. Write registers (RIP + RSP)
       Put_String ("[S8.1D] WriteRegs... ");
       R := TCB_Write_Registers (Net_TCB_Slot, NetServer_Entry_Addr, NetServer_Stack_Addr);
       Put_Hex (R); Put_String (ASCII.CR & ASCII.LF);
       if R /= 0 then return 2; end if;

       -- 8. Set net endpoint CPtr
       declare
          procedure Set_Net_EP (EP : Word)
            with Import, Convention => C, External_Name => "schild_set_net_endpoint";
          procedure Set_Net_Reply (Rpl : Word)
            with Import, Convention => C, External_Name => "schild_set_net_reply";
       begin
          Set_Net_EP (Net_EP_CPtr);
          Set_Net_Reply (Net_Reply_CPtr);
       end;

       -- 9. Resume NetServer
       Put_String ("[S8.1D] Resume... ");
       R := TCB_Resume (Net_TCB_Slot);
       Put_Hex (R); Put_String (ASCII.CR & ASCII.LF);
       if R /= 0 then return 2; end if;

       -- Health Monitoring: remember NetServer TCB/entry/stack for restart.
       Net_TCB_Cap := Net_TCB_Slot;
       Net_Entry    := NetServer_Entry_Addr;
       Net_Stack    := NetServer_Stack_Addr;

       -- 10. Yield to let NetServer start its Recv loop
       Yield;

       -- 11. IPC test: Call op=0 (init) -> expect reply status 0
       Put_String ("[S8.1D] IPC Call (init)... ");
       R := Call_IPC (Net_EP_Slot, 0, 0);
       Put_Hex (R); Put_String (ASCII.CR & ASCII.LF);
       Put_String ("[S8.1D] Reply status: ");
       Put_Hex (Read_IPC_MR0); Put_String (ASCII.CR & ASCII.LF);

       Put_String ("[S8.1D] NetServer launched" & ASCII.CR & ASCII.LF);
       Schild_HM_Model.Launch (HM_St, Schild_HM_Model.HM_NetServer);
       Schild_Launch_Model.Launch
         (Launch_St, Schild_Launch_Model.NetServer, Natural (Net_Fault_Root_Slot));
       return 0;
    end Launch_NetServer;

    -- ==========================================================================
    -- Stage 8.3: wire the e1000e IRQ to a (badged) Notification.
    --   notification@4116 → badged copy@4118 (badge 0xE1) → IRQHandler@4117.
    -- The Root Task's idle loop waits on the badge, forwards a poll_rx Call to
    -- the NetServer (which reads ICR and dispatches), then acks the IRQ.
    -- ==========================================================================
    function Init_NetServer_IRQ return Word is
       BI : constant BI_Access := Get_BootInfo;
       IRQ_Control_Slot : constant Cap_Ref := 4;    -- seL4_CapIRQControl
       -- Slot constants (IRQ_Ntfn_Slot, IRQ_Handler_Slot, IRQ_Ntfn_Badged_Slot)
       -- come from the package specification's slot map.
       Root_Depth       : constant Word := 64;      -- wordBits (root CNode)
       -- QEMU e1000 (82540EM @ PCI 00:03.0) INTx -> PIIX3 PIRQ -> GSI.
       -- GSI=11 is the documented QEMU default for the i440fx e1000; MUST be
       -- validated on a tap/socket backend or real hardware (T580), where the
       -- PCI-scan + MSI detection path is required anyway (TODO P1).
       Net_GSI      : constant Word := 11;
       Net_IOAPIC   : constant Word := 0;
       Net_Level    : constant Word := 1;   -- level-triggered
       Net_Polarity : constant Word := 0;   -- active-high (MADT ISO flags 0xd)
       Net_IRQ_Id   : constant Word := 0;   -- relative to irq_user_min(16)
       UT : Cap_Ref := 0;
       R  : Word;
    begin
       -- 1. RAM untyped for the notification object.
       for I in 1 .. N_UNTYPED loop
          if BI.all.Untyped_List (I).Size_Bits >= 20
            and then BI.all.Untyped_List (I).Is_Device = 0
            and then BI.all.Untyped_List (I).PAddr >= 16#800000#
          then
             UT := BI.all.Untyped_Start + Word (I - 1);
             exit;
          end if;
       end loop;
       if UT = 0 then
          Put_String ("[S8.3] FATAL: no RAM untyped for IRQ notification" & ASCII.CR & ASCII.LF);
          return 1;
       end if;

       -- 2. Notification object @ 4116.
       R := Retype_Object (UT, Object_Notification, 0, CNode_Slot, 0, IRQ_Ntfn_Slot, 1);
       if R /= 0 then
          Put_String ("[S8.3] Retype notification FAIL"); Put_Hex (R);
          Put_String (ASCII.CR & ASCII.LF); return 2;
       end if;

       -- 3. Badged copy @ 4118 (badge 0xE1) so NBRecv can detect the signal.
       R := CNode_Mint (CNode_Slot, IRQ_Ntfn_Badged_Slot, Root_Depth,
                        CNode_Slot, IRQ_Ntfn_Slot, Root_Depth, 16#F#, 16#E1#);
       if R /= 0 then
          Put_String ("[S8.3] Mint badge FAIL"); Put_Hex (R);
          Put_String (ASCII.CR & ASCII.LF); return 3;
       end if;

       -- 4. IRQHandler @ 4117.  W2: MSI for the real I219-V, IOAPIC INTx for
       -- the QEMU 82540EM fallback.
       if Nic_Is_Real then
          declare
             Msg_Handle : constant Word := 16#30#;
             Msg_Irq    : constant Word := 0;
          begin
             R := IRQ_Control_Get_MSI (IRQ_Control_Slot, IRQ_Handler_Slot, Root_Depth,
                                       Nic_Bus, Nic_Dev, Nic_Func, Msg_Handle, Msg_Irq,
                                       CNode_Slot);
             if R /= 0 then
                Put_String ("[S8.3] IRQControl_GetMSI FAIL"); Put_Hex (R);
                Put_String (ASCII.CR & ASCII.LF); return 4;
             end if;
             if not Program_MSI (Nic_Bus, Nic_Dev, Nic_Func, Msg_Handle) then
                Put_String ("[S8.3] MSI capability program FAIL" & ASCII.CR & ASCII.LF);
                return 6;
             end if;
             Put_String ("[S8.3] e1000e MSI programmed (vector 0x30)" & ASCII.CR & ASCII.LF);
          end;
       else
          R := IRQ_Control_Get_IOAPIC (IRQ_Control_Slot, IRQ_Handler_Slot, Root_Depth,
                                       Net_IOAPIC, Net_GSI, Net_Level, Net_Polarity,
                                       Net_IRQ_Id, CNode_Slot);
          if R /= 0 then
             Put_String ("[S8.3] IRQControl_Get FAIL"); Put_Hex (R);
             Put_String (ASCII.CR & ASCII.LF); return 4;
          end if;
       end if;

       -- 5. Bind the IRQ handler to the badged notification.
       R := IRQ_Handler_Set_Notification (IRQ_Handler_Slot, IRQ_Ntfn_Badged_Slot);
       if R /= 0 then
          Put_String ("[S8.3] SetNotification FAIL"); Put_Hex (R);
          Put_String (ASCII.CR & ASCII.LF); return 5;
       end if;

       Put_String ("[S8.3] e1000e IRQ wired: ntfn@4118 (badge 0xE1), handler@4117, GSI=");
       Put_Dec (Net_GSI);
       Put_String (ASCII.CR & ASCII.LF);
       return 0;
    end Init_NetServer_IRQ;

    -- ==========================================================================
    -- Stage 8.4: shared DMA frame for large-frame transfer (no MR limit).
    --   Retype a 4KB frame @4125, mint a copy @4126, map the original into the
    --   Root VSpace and the copy into the NetServer VSpace, both at 0x52A000
    --   (moved off 0x520000, now the R4 per-level MLS ring region).
    --   Both processes then exchange frames > 960 B through this shared page.
    -- ==========================================================================
    function Init_NetServer_Shared_Frame return Word is
       BI : constant BI_Access := Get_BootInfo;
       Shared_Slot  : constant Cap_Ref := Shared_Frame_Slot;
       Shared_Copy  : constant Cap_Ref := Shared_Frame_Copy_Slot;
       Shared_VAddr : constant Word := 16#52A000#;
       Root_VSpace  : constant Cap_Ref := 3;    -- seL4_CapInitThreadVSpace
       Net_VSpace   : constant Cap_Ref := Net_PML4_Slot;  -- NetServer PML4
       Root_Depth   : constant Word := 64;
       UT : Cap_Ref := 0;
       R  : Word;
    begin
       -- 1. RAM untyped (>= 1MB) for the shared frame.
       for I in 1 .. N_UNTYPED loop
          if BI.all.Untyped_List (I).Size_Bits >= 20
            and then BI.all.Untyped_List (I).Is_Device = 0
            and then BI.all.Untyped_List (I).PAddr >= 16#800000#
          then
             UT := BI.all.Untyped_Start + Word (I - 1);
             exit;
          end if;
       end loop;
       if UT = 0 then
          Put_String ("[S8.4] FATAL: no RAM untyped for shared frame" & ASCII.CR & ASCII.LF);
          return 1;
       end if;

       -- 2. Retype a 4KB frame @ 4125.
       R := Retype_Object (UT, Object_Frame, 0, CNode_Slot, 0, Shared_Slot, 1);
       if R /= 0 then return 2; end if;

       -- 3. Mint a copy @ 4126 (a frame cap maps once per cap).
       R := CNode_Mint (CNode_Slot, Shared_Copy, Root_Depth,
                        CNode_Slot, Shared_Slot, Root_Depth, 16#F#, 0);
       if R /= 0 then return 3; end if;

       -- 4. Map @ 4125 into the Root VSpace @ 0x520000.
       R := Page_Map (Shared_Slot, Root_VSpace, Shared_VAddr);
       if R /= 0 then return 4; end if;

       -- 5. Map @ 4126 into the NetServer VSpace @ 0x520000.
       R := Page_Map (Shared_Copy, Net_VSpace, Shared_VAddr);
       if R /= 0 then return 5; end if;

       Put_String ("[S8.4] shared frame mapped @0x520000 (both VSpaces)" & ASCII.CR & ASCII.LF);
       return 0;
    end Init_NetServer_Shared_Frame;

    -- Stage 8.4 demo: round-trip a 64-byte frame through the shared DMA frame.
    -- Uses 'Address (forbidden in SPARK On), so it lives in this Off body.
    function Demo_Shared_Frame return Word is
       Frame : array (0 .. 63) of U8 := (others => 16#AA#);
       LR    : Word := 0;
       Echo  : Word := 0;
    begin
       Frame (0) := 16#5A#;
       Shared_Copy_To (Frame'Address, 64);
       LR := Call_IPC (Net_EP_Slot, 2, 64);
       Echo := Read_IPC_MR1;
       Put_String ("[S8.4] tx_frame echo: 0x");
       Put_Hex (Echo);
       Put_String ("  (expect 0x5A)" & ASCII.CR & ASCII.LF);
       return LR;
    end Demo_Shared_Frame;

    -- ==========================================================================
    -- R4: per-level MLS SPSC rings + directional (RO/RW) mapping.
    --   Retype 5 data frames D[0..4] (Tail+Data) + 5 cursor frames C[0..4]
    --   (Head), mint each, then map with hard VM rights:
    --     D[L] -> Root VSpace RW (producer writes), NetServer VSpace RO;
    --     C[L] -> NetServer VSpace RW (consumer writes), Root VSpace RO.
    --   Addresses: D[L] = 0x520000 + L*0x1000, C[L] = 0x525000 + L*0x1000.
    --   Slots: frames 4130..4139, mints 4140..4149.
    -- ==========================================================================
    function Init_Mls_Rings return Word is
       BI : constant BI_Access := Get_BootInfo;
       Root_VSpace : constant Cap_Ref := 3;    -- seL4_CapInitThreadVSpace
       Net_VSpace  : constant Cap_Ref := Net_PML4_Slot;  -- NetServer PML4
       Root_Depth  : constant Word := 64;
       -- seL4 VM-rights word (CapRights layout): bit0=Write, bit1=Read.
       RW : constant Word := 3;  -- seL4_ReadWrite = Read|Write (0x03)
       RO : constant Word := 2;  -- seL4_CanRead = Read (0x02), NOT 1 (= Write!)
       Data_Base : constant Word := 16#520000#;
       Head_Base : constant Word := 16#525000#;
       UT : Cap_Ref := 0;
       R  : Word;
    begin
       -- 1. RAM untyped (>= 1MB) for the 10 frames.
       for I in 1 .. N_UNTYPED loop
          if BI.all.Untyped_List (I).Size_Bits >= 20
            and then BI.all.Untyped_List (I).Is_Device = 0
            and then BI.all.Untyped_List (I).PAddr >= 16#800000#
          then UT := BI.all.Untyped_Start + Word (I - 1); exit; end if;
       end loop;
       if UT = 0 then
          Put_String ("[R4] FATAL: no RAM untyped for MLS rings" & ASCII.CR & ASCII.LF);
          return 1;
       end if;
       -- 2. Retype + mint + map each of the 5 levels.
       for L in 0 .. 4 loop
          R := Retype_Object (UT, Object_Frame, 0, CNode_Slot, 0, MLS_Rings_Data_Base + Word (L), 1);
          if R /= 0 then return 2; end if;
          R := Retype_Object (UT, Object_Frame, 0, CNode_Slot, 0, MLS_Rings_Head_Base + Word (L), 1);
          if R /= 0 then return 3; end if;
          R := CNode_Mint (CNode_Slot, MLS_Rings_Data_Mint_Base + Word (L), Root_Depth,
                           CNode_Slot, MLS_Rings_Data_Base + Word (L), Root_Depth, 16#F#, 0);
          if R /= 0 then return 4; end if;
          R := CNode_Mint (CNode_Slot, MLS_Rings_Head_Mint_Base + Word (L), Root_Depth,
                           CNode_Slot, MLS_Rings_Head_Base + Word (L), Root_Depth, 16#F#, 0);
          if R /= 0 then return 5; end if;
          -- D[L]: producer (Root) RW, consumer (NetServer) RO.
          R := Page_Map_Rights (MLS_Rings_Data_Base + Word (L), Root_VSpace,
                                Data_Base + Word (L) * 16#1000#, RW);
          if R /= 0 then return 6; end if;
          R := Page_Map_Rights (MLS_Rings_Data_Mint_Base + Word (L), Net_VSpace,
                                Data_Base + Word (L) * 16#1000#, RO);
          if R /= 0 then return 7; end if;
          -- C[L]: consumer (NetServer) RW, producer (Root) RO.
          R := Page_Map_Rights (MLS_Rings_Head_Mint_Base + Word (L), Net_VSpace,
                                Head_Base + Word (L) * 16#1000#, RW);
          if R /= 0 then return 8; end if;
          R := Page_Map_Rights (MLS_Rings_Head_Base + Word (L), Root_VSpace,
                                Head_Base + Word (L) * 16#1000#, RO);
          if R /= 0 then return 9; end if;
       end loop;
       Put_String ("[R4] 5 per-level MLS rings mapped (RO/RW split)" & ASCII.CR & ASCII.LF);
       return 0;
    end Init_Mls_Rings;

end Schild_Sel4_Syscall;
