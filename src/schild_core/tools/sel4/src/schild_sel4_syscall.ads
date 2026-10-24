-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- =============================================================================
-- Schild TCB — seL4 syscall bindings for Ada/SPARK (x86_64, CONFIG_SYSCALL)
--
-- CONTRACT BOUNDARY (W4): the *specification* is SPARK_Mode => On, so its types
-- (Word, Cap_Ref, HM_Domain) and operations are SPARK-visible with contracts
-- (Global => null, Pre on slot-validity).  The *body* stays SPARK_Mode => Off —
-- it is the seL4 mechanism (retype / map / MMIO / MSI / TCB*), which is trusted
-- axiomatic behavior, not proved.  Policy lives in the On packages
-- (Schild_Launch_Model, Schild_HM_Model); this package is the mechanism seam.
-- =============================================================================

with Interfaces; use Interfaces;
with System;

package Schild_Sel4_Syscall
  with SPARK_Mode => On
is
   -- seL4 word types (64-bit on x86_64)
   subtype Word is Unsigned_64;
   subtype Cap_Ref is Word;
   subtype Message_Info is Word;

   -- ========================================================================
   --  Root-task CSpace slot map
   --
   --  The root CNode is 2^19 slots (524288).  The boot-time untyped-cap region
   --  occupies slots [Untyped_Start .. Untyped_End); with the 32 GB T580 and
   --  CONFIG_MAX_NUM_BOOTINFO_UNTYPED_CAPS=500 that region ends at ~577 (the
   --  measured Untyped_Start on this build is 77).  Every dynamically-created
   --  object (endpoints, TCBs, frames, VSpace structures, frame regions) is
   --  placed at a slot >= Slot_Base so it can never collide with the untyped
   --  region, no matter how fragmented the platform memory map is.
   -- ========================================================================
   Slot_Base : constant Cap_Ref := 4096;

   -- MLS server (Stage 7.7)
   MLS_EP_Slot         : constant Cap_Ref := Slot_Base + 0;   -- 4096
   MLS_Fault_Slot      : constant Cap_Ref := Slot_Base + 1;   -- 4097
   MLS_TCB_Slot        : constant Cap_Ref := Slot_Base + 2;   -- 4098
   MLS_IPC_Frame_Slot  : constant Cap_Ref := Slot_Base + 3;   -- 4099
   MLS_SC_Slot         : constant Cap_Ref := Slot_Base + 4;   -- 4100
   MLS_Reply_Slot      : constant Cap_Ref := Slot_Base + 5;   -- 4101

   -- NetServer (Stage 8.1/8.2)
   Net_EP_Slot         : constant Cap_Ref := Slot_Base + 6;   -- 4102
   Net_TCB_Slot        : constant Cap_Ref := Slot_Base + 7;   -- 4103
   Net_IPC_Slot        : constant Cap_Ref := Slot_Base + 8;   -- 4104
   Net_CSpace_Slot     : constant Cap_Ref := Slot_Base + 9;   -- 4105
   Net_PML4_Slot       : constant Cap_Ref := Slot_Base + 10;  -- 4106
   Net_PDPT_Slot       : constant Cap_Ref := Slot_Base + 11;  -- 4107
   Net_PD_Slot         : constant Cap_Ref := Slot_Base + 12;  -- 4108
   Net_PT_Lo_Slot      : constant Cap_Ref := Slot_Base + 13;  -- 4109
   Net_PT_Mmio_Slot    : constant Cap_Ref := Slot_Base + 14;  -- 4110
   Net_SC_Slot         : constant Cap_Ref := Slot_Base + 15;  -- 4111
   Net_Reply_Slot      : constant Cap_Ref := Slot_Base + 16;  -- 4112
   Net_Fault_Root_Slot : constant Cap_Ref := Slot_Base + 17;  -- 4113

   -- Root task fault handler + IRQ (Stage 6 / 8.3)
   Root_Fault_EP_Slot  : constant Cap_Ref := Slot_Base + 18;  -- 4114
   Timeout_EP_Slot     : constant Cap_Ref := Slot_Base + 19;  -- 4115
   IRQ_Ntfn_Slot       : constant Cap_Ref := Slot_Base + 20;  -- 4116
   IRQ_Handler_Slot    : constant Cap_Ref := Slot_Base + 21;  -- 4117
   IRQ_Ntfn_Badged_Slot : constant Cap_Ref := Slot_Base + 22; -- 4118

   -- Config Daemon (R3)
   Config_EP_Slot      : constant Cap_Ref := Slot_Base + 23;  -- 4119
   Config_Fault_Slot   : constant Cap_Ref := Slot_Base + 24;  -- 4120
   Config_TCB_Slot     : constant Cap_Ref := Slot_Base + 25;  -- 4121
   Config_IPC_Frame_Slot : constant Cap_Ref := Slot_Base + 26; -- 4122
   Config_SC_Slot      : constant Cap_Ref := Slot_Base + 27;  -- 4123
   Config_Reply_Slot   : constant Cap_Ref := Slot_Base + 28;  -- 4124

   -- Shared DMA frame (Stage 8.4)
   Shared_Frame_Slot      : constant Cap_Ref := Slot_Base + 29; -- 4125
   Shared_Frame_Copy_Slot : constant Cap_Ref := Slot_Base + 30; -- 4126

   -- W2: ECAM (MMCONFIG) window frame — 2 MiB large page @ 0xF0000000.
   Ecam_Frame_Slot        : constant Cap_Ref := Slot_Base + 31; -- 4127

   -- R4 per-level MLS rings: frames/mints (20 slots, 4130..4149)
   MLS_Rings_Data_Base      : constant Cap_Ref := Slot_Base + 34; -- 4130
   MLS_Rings_Head_Base      : constant Cap_Ref := Slot_Base + 39; -- 4135
   MLS_Rings_Data_Mint_Base : constant Cap_Ref := Slot_Base + 44; -- 4140
   MLS_Rings_Head_Mint_Base : constant Cap_Ref := Slot_Base + 49; -- 4145

   -- Large frame regions (image frames + MMIO frames).
   Image_Frame_Base : constant Cap_Ref := Slot_Base + 128;  -- 4224
   MMIO_Frame_Base  : constant Cap_Ref := Slot_Base + 512;  -- 4608


   -- ========================================================================
   --  Basic Syscalls
   -- ========================================================================

   procedure Yield
     with Import, Convention => C, External_Name => "schild_sel4_yield",
          Global => null;

   -- Blocking receive WITHOUT a reply object (MCS SysWait).  Used by the root
   -- task to receive faults on the fault endpoint (faults are plain Sends).
   function Wait (Src : Cap_Ref) return Word
     with Import, Convention => C, External_Name => "schild_sel4_wait",
          Global => null,
          Pre => Src > 0;

   -- Non-blocking receive WITHOUT a reply object (MCS SysNBWait).  Used by the
   -- root task to poll the e1000e IRQ notification.  badge=0 => nothing pending.
   function NBWait (Src : Cap_Ref) return Word
     with Import, Convention => C, External_Name => "schild_sel4_nbwait",
          Global => null,
          Pre => Src > 0;

   procedure Debug_Put_Char (C : Unsigned_32)
     with Import, Convention => C, External_Name => "schild_sel4_debug_putchar",
          Global => null;

   procedure Put_String (S : String)
     with Global => null;

   procedure Pause
     with Import, Convention => C, External_Name => "schild_pause",
          Global => null;

   procedure Fault_Guard
     with Global => null;

   -- Health Monitoring domains (ARINC 653 "fault -> action").
   type HM_Domain is (HM_NetServer, HM_MLS, HM_Config_Daemon);

   -- Restart the given faulted domain (TCBWriteRegisters + TCBResume).
   procedure Health_Monitor (Domain : HM_Domain)
     with Global => null;

   -- ========================================================================
   --  Object Creation & Configuration
   -- ========================================================================

   function TCB_Set_Fault_Handler
     (TCB_Cap      : Cap_Ref;
      Fault_EP     : Cap_Ref;
      CSpace_Root  : Cap_Ref;
      CSpace_Data  : Word;
      VSpace_Root  : Cap_Ref;
      VSpace_Data  : Word) return Word
     with Import, Convention => C, External_Name => "schild_sel4_tcb_set_fault_handler",
          Global => null,
          Pre => TCB_Cap > 0 and CSpace_Root > 0 and VSpace_Root > 0;

   function Init_Fault_Handler return Word
     with Global => null;

   function Retype_Object
     (Untyped_Cap : Cap_Ref;
      Object_Type : Word;
      Size_Bits   : Word;
      Root_CNode  : Cap_Ref;
      Node_Depth  : Word;
      Dest_Slot   : Cap_Ref;
      Num_Objects : Word) return Word
     with Import, Convention => C, External_Name => "schild_sel4_retype_object",
          Global => null,
          Pre => Untyped_Cap > 0 and Root_CNode > 0 and Num_Objects > 0;

   function CNode_Mint
     (Dest_CNode : Cap_Ref;
      Dest_Index : Word;
      Dest_Depth : Word;
      Src_CNode  : Cap_Ref;
      Src_Index  : Word;
      Src_Depth  : Word;
      Rights     : Word;
      Badge      : Word) return Word
     with Import, Convention => C, External_Name => "schild_sel4_cnode_mint",
          Global => null,
          Pre => Dest_CNode > 0 and Src_CNode > 0;

   function TCB_Resume (TCB_Cap : Cap_Ref) return Word
     with Import, Convention => C, External_Name => "schild_sel4_tcb_resume",
          Global => null,
          Pre => TCB_Cap > 0;

   function ASID_Pool_Assign
     (Pool   : Cap_Ref;
      VSpace : Cap_Ref) return Word
     with Import, Convention => C, External_Name => "schild_sel4_x86_asid_pool_assign",
          Global => null,
          Pre => Pool > 0 and VSpace > 0;

   function PDPT_Map
     (PDPT_Cap   : Cap_Ref;
      VSpace_Cap : Cap_Ref;
      VAddr      : Word) return Word
     with Import, Convention => C, External_Name => "schild_sel4_x86_pdpt_map",
          Global => null,
          Pre => PDPT_Cap > 0 and VSpace_Cap > 0;

   function Page_Directory_Map
     (PD_Cap     : Cap_Ref;
      VSpace_Cap : Cap_Ref;
      VAddr      : Word) return Word
     with Import, Convention => C, External_Name => "schild_sel4_x86_page_directory_map",
          Global => null,
          Pre => PD_Cap > 0 and VSpace_Cap > 0;

   function TCB_Write_Registers
     (TCB_Cap : Cap_Ref;
      RIP_Addr : Word;
      RSP_Addr : Word) return Word
     with Import, Convention => C, External_Name => "schild_sel4_tcb_write_registers",
          Global => null,
          Pre => TCB_Cap > 0 and RIP_Addr /= 0 and RSP_Addr /= 0;

   -- ========================================================================
   --  IPC Operations
   -- ========================================================================

   function Call_IPC (Dest : Cap_Ref; MR0 : Word; MR1 : Word) return Word
     with Import, Convention => C, External_Name => "schild_sel4_call",
          Global => null,
          Pre => Dest > 0;

   function Read_IPC_MR0 return Word
     with Import, Convention => C, External_Name => "schild_read_ipc_mr0",
          Global => null;

   -- Read recv MR[0] captured by Wait/Recv (timeout-fault SC badge).
   function Read_Recv_MR0 return Word
     with Import, Convention => C, External_Name => "schild_read_recv_mr0",
          Global => null;

   -- ========================================================================
   --  Memory Management
   -- ========================================================================

   function Page_Map
     (Page_Cap   : Cap_Ref;
      VSpace_Cap : Cap_Ref;
      VAddr      : Word) return Word
     with Import, Convention => C, External_Name => "schild_sel4_x86_page_map",
          Global => null,
          Pre => Page_Cap > 0 and VSpace_Cap > 0
                 and (VAddr mod 4096) = 0;

   -- Map a 4K frame into a VSpace with explicit VM rights (3=RW, 1=RO).
   -- R4 directional mapping: the producer page is RW, the consumer page RO.
   function Page_Map_Rights
     (Page_Cap   : Cap_Ref;
      VSpace_Cap : Cap_Ref;
      VAddr      : Word;
      Rights     : Word) return Word
     with Import, Convention => C, External_Name => "schild_sel4_x86_page_map_rights",
          Global => null,
          Pre => Page_Cap > 0 and VSpace_Cap > 0
                 and (VAddr mod 4096) = 0;

   function Page_Table_Map
     (PT_Cap     : Cap_Ref;
      VSpace_Cap : Cap_Ref;
      VAddr      : Word) return Word
     with Import, Convention => C, External_Name => "schild_sel4_x86_page_table_map",
          Global => null,
          Pre => PT_Cap > 0 and VSpace_Cap > 0
                 and (VAddr mod 4096) = 0;

   function Page_Get_Address
     (Page_Cap : Cap_Ref) return Word
     with Import, Convention => C, External_Name => "schild_sel4_x86_page_get_address",
          Global => null,
          Pre => Page_Cap > 0;

   procedure Set_DMA_Offset (Offset : Word)
     with Import, Convention => C, External_Name => "schild_set_dma_offset",
          Global => null;

   -- Compute the virtual->physical offset of the root task image and install
   -- it for the DMA helpers (schild_dma_phys).  Returns 0 on success.
   function Init_NetServer_DMA return Word
     with Global => null;

   -- Launch the NetServer process (net_ep endpoint + TCB + IPC buffer), then
   -- run an IPC test (Call op=init -> Reply status).  Returns 0 on success.
   function Launch_NetServer return Word
     with Global => null;

   function TCB_Set_IPC_Buffer
     (TCB_Cap  : Cap_Ref;
      Buf_Cap  : Cap_Ref;
      Buf_Addr : Word) return Word
     with Import, Convention => C, External_Name => "schild_sel4_tcb_set_ipc_buffer",
          Global => null,
          Pre => TCB_Cap > 0 and Buf_Cap > 0;

   -- ========================================================================
   --  MCS scheduling contexts (SchedControl / SchedContext)
   -- ========================================================================

   -- Populate a scheduling context with a CPU budget (budget/period in us;
   -- budget = period yields a round-robin context).
   function SchedControl_ConfigureFlags
     (SchedControl  : Cap_Ref;
      SchedContext  : Cap_Ref;
      Budget        : Word;
      Period        : Word;
      Extra_Refills : Word;
      Badge         : Word;
      Flags         : Word) return Word
     with Import, Convention => C, External_Name => "schild_sel4_schedcontrol_configureflags",
          Global => null,
          Pre => SchedControl > 0 and SchedContext > 0;

   -- Bind a TCB to a (already configured) scheduling context.
   function SchedContext_Bind (SchedContext : Cap_Ref; TCB_Cap : Cap_Ref)
                               return Word
     with Import, Convention => C, External_Name => "schild_sel4_schedcontext_bind",
          Global => null,
          Pre => SchedContext > 0 and TCB_Cap > 0;

   -- Set the endpoint that receives timeout faults when the thread's SC budget
   -- is exhausted (sporadic, budget < period).  MCS only.
   function TCB_Set_Timeout_Endpoint (TCB_Cap : Cap_Ref; Timeout_EP : Cap_Ref)
                                      return Word
     with Import, Convention => C, External_Name => "schild_sel4_tcb_set_timeout_endpoint",
          Global => null,
          Pre => TCB_Cap > 0 and Timeout_EP > 0;

   -- ========================================================================
   --  High-Level Operations
   -- ========================================================================

   function Launch_MLS_Server return Word
     with Global => null;

   -- Create a dedicated VSpace (PML4) for NetServer and map its image, IPC
   -- buffer and e1000e BAR0 MMIO (128 KB) into it.  Returns the new VSpace
   -- cap slot on success, 0 on error.
   function Map_NetServer_VSpace return Word
     with Global => null;

   -- ========================================================================
   --  IRQ Operations (Stage 8.3: e1000e interrupt-driven RX)
   -- ========================================================================

   function IRQ_Control_Get_IOAPIC
     (IRQ_Control : Cap_Ref;
      Index       : Word;
      Depth       : Word;
      IOAPIC      : Word;
      Pin         : Word;
      Level       : Word;
      Polarity    : Word;
      IRQ         : Word;
      Root_CNode  : Cap_Ref) return Word
     with Import, Convention => C, External_Name => "schild_sel4_irq_control_get_ioapic",
          Global => null,
          Pre => IRQ_Control > 0 and Root_CNode > 0;
   function IRQ_Control_Get_MSI
     (IRQ_Control : Cap_Ref;
      Index       : Word;
      Depth       : Word;
      PCI_Bus     : Word;
      PCI_Dev     : Word;
      PCI_Func    : Word;
      Handle      : Word;
      IRQ         : Word;
      Root_CNode  : Cap_Ref) return Word
     with Import, Convention => C, External_Name => "schild_sel4_irq_control_get_msi",
          Global => null,
          Pre => IRQ_Control > 0 and Root_CNode > 0;

   function IRQ_Handler_Set_Notification
     (IRQ_Handler : Cap_Ref;
      Ntfn        : Cap_Ref) return Word
     with Import, Convention => C, External_Name => "schild_sel4_irq_handler_set_notification",
          Global => null,
          Pre => IRQ_Handler > 0 and Ntfn > 0;

   function IRQ_Handler_Ack (IRQ_Handler : Cap_Ref) return Word
     with Import, Convention => C, External_Name => "schild_sel4_irq_handler_ack",
          Global => null,
          Pre => IRQ_Handler > 0;

   -- Wire the e1000e IRQ to a (badged) Notification: retype a notification,
   -- mint a badged copy, create an IRQHandler and bind it.  Returns 0 on
   -- success.  Slots used: 503 (notification), 504 (IRQHandler), 505 (badged).
   function Init_NetServer_IRQ return Word
     with Global => null;

   -- ========================================================================
   --  Shared DMA frame (Stage 8.4: large-frame transfer, no MR limit)
   -- ========================================================================

   -- Copy Len bytes from Src into the shared frame at 0x520000.
   procedure Shared_Copy_To (Src : System.Address; Len : Unsigned_32)
     with Import, Convention => C, External_Name => "schild_shared_copy_to",
          Global => null;

   -- Read the secondary reply word (reply MR[1]) captured by Call_IPC.
   function Read_IPC_MR1 return Word
     with Import, Convention => C, External_Name => "schild_read_ipc_mr1",
          Global => null;

   -- Retype a 4KB frame, map it into BOTH the Root VSpace and the NetServer
   -- VSpace at 0x52A000 (shared).  Returns 0 on success.
   function Init_NetServer_Shared_Frame return Word
     with Global => null;

   -- Stage 8.4 demo: place a 64-byte test frame (first byte 0x5A) in the shared
   -- DMA frame, TX via op=2, and echo-verify the first byte.  Mechanism (uses
   -- 'Address + DMA), so its body is SPARK_Mode => Off; the Global contract makes
   -- it callable from the On driver.
   function Demo_Shared_Frame return Word
     with Global => null;

   -- R4: retype + mint + map 5 per-level MLS SPSC rings (10 frames) with
   -- directional (RO/RW) VM rights.  Returns 0 on success.
   function Init_Mls_Rings return Word
     with Global => null;

   -- R3: launch the isolated Config Daemon process (own fault domain).
   function Launch_Config_Daemon return Word
     with Global => null;

end Schild_Sel4_Syscall;
