-- Schild TCB — mini-bootstrap (root task as ELF-child, Phase B).
-- First userspace thread. Phase B: read BootInfo, retype a PML4 + page
-- tables, Load_Elf(root_task.elf) into that VSpace, TCB_Resume the root task
-- (ROOT_TASK_ELF_CHILD_DESIGN.md).
with Schild_Sel4_BootInfo;
with Schild_Sel4_Syscall; use Schild_Sel4_Syscall;
with Schild_Elf_Loader;
with Interfaces;         use Interfaces;
with System;

procedure Schild_Bootstrap with SPARK_Mode => Off is
   -- Read the seL4 BootInfo frame as a VALUE via the C memcpy shim (same as
   -- Schild_Root_Task).
   procedure Get_BootInfo_Copy (BI : out Schild_Sel4_BootInfo.BootInfo; Nbytes : Unsigned_64)
     with Import, Convention => C, External_Name => "schild_get_bootinfo_copy",
          Global => null;

   -- Embedded root_task.elf blob (ld -r -b binary) — accessors from bootstrap.c.
   function Root_Task_Elf_Start return Unsigned_64
     with Import, Convention => C, External_Name => "bootstrap_root_task_elf_start";
   function Root_Task_Elf_Size return Unsigned_64
     with Import, Convention => C, External_Name => "bootstrap_root_task_elf_size";

   -- Debug marker (single char via seL4_DebugPutChar) — Phase B bring-up.
   procedure Debug_Put (C : Unsigned_64)
     with Import, Convention => C, External_Name => "schild_sel4_debug_putchar";

   BI : Schild_Sel4_BootInfo.BootInfo;
   R : Unsigned_64;
   Load_Status : Unsigned_64;
   Load_Entry  : Unsigned_64;
   UT : Cap_Ref := 0;
   CNode_Slot : constant Cap_Ref := 2;   -- seL4_CapInitThreadCNode
   Root_VSpace : constant Cap_Ref := 3;
begin
   Get_BootInfo_Copy (BI, Unsigned_64 (Schild_Sel4_BootInfo.BootInfo'Size / System.Storage_Unit));

   -- CRITICAL: set the IPC buffer address (schild_ipc_buf_addr) from the boot
   -- info, else set_mr/set_ec write to NULL+offset (same as the root task's
   -- Init_IPC in schild_sel4_syscall.adb).
   declare
      function Get_BI_Frame return Unsigned_64
        with Import, Convention => C, External_Name => "schild_get_bootinfo_frame";
      procedure Dump_Raw_BI (Frame : Unsigned_64)
        with Import, Convention => C, External_Name => "schild_dump_raw_bootinfo";
   begin
      Dump_Raw_BI (Get_BI_Frame);
   end;

   -- Find a large RAM untyped for the root task's VSpace objects + image
   -- frames (~1087 pages, MemSiz ~4.25 MB) — needs Size_Bits >= 23 (8 MB).
   for I in BI.Untyped_List'Range loop
      if BI.Untyped_List (I).Size_Bits >= 23
        and then BI.Untyped_List (I).Is_Device = 0
      then
         UT := BI.Untyped_Start + Word (I - 1);
         exit;
      end if;
   end loop;
   if UT = 0 then
      return;
   end if;

   -- Retype the root task's page tables (PML4/PDPT/PD/PT_Lo).
   R := Retype_Object (UT, Object_PML4, 0, CNode_Slot, 0, Bootstrap_PML4_Slot, 1);
   if R /= 0 then return; end if;
   R := Retype_Object (UT, Object_PDPT, 0, CNode_Slot, 0, Bootstrap_PDPT_Slot, 1);
   if R /= 0 then return; end if;
   R := Retype_Object (UT, Object_PageDirectory, 0, CNode_Slot, 0, Bootstrap_PD_Slot, 1);
   if R /= 0 then return; end if;
   R := Retype_Object (UT, Object_PageTable, 0, CNode_Slot, 0, Bootstrap_PT_Lo_Slot, 1);
   if R /= 0 then return; end if;

   -- Assign an ASID and map the page tables (root task image at 0x400000).
   R := ASID_Pool_Assign (6, Bootstrap_PML4_Slot);
   if R /= 0 then return; end if;
   R := PDPT_Map (Bootstrap_PDPT_Slot, Bootstrap_PML4_Slot, 0);
   if R /= 0 then return; end if;
   R := Page_Directory_Map (Bootstrap_PD_Slot, Bootstrap_PML4_Slot, 0);
   if R /= 0 then return; end if;
   R := Page_Table_Map (Bootstrap_PT_Lo_Slot, Bootstrap_PML4_Slot, 16#400000#);
   if R /= 0 then return; end if;

   -- Load the root task ELF into its new VSpace.
   Schild_Elf_Loader.Load_Elf (Root_Task_Elf_Start, Root_Task_Elf_Size,
                               Bootstrap_PML4_Slot, Root_VSpace, UT, CNode_Slot,
                               Bootstrap_Image_Frame_Base, Bootstrap_Mint_Offset,
                               Load_Status, Load_Entry);
   if Load_Status /= 0 then
      return;
   end if;
   Debug_Put (76);  -- 'L': Load_Elf OK

   -- Phase B part 2: retype TCB + SchedContext + Reply + IPC frame, MCS
   -- configure + bind, fault handler + IPC buffer, write registers + resume.
   R := Retype_Object (UT, Object_TCB, 0, CNode_Slot, 0, Bootstrap_TCB_Slot, 1);
   if R /= 0 then return; end if;
   R := Retype_Object (UT, Object_SchedContext, 7, CNode_Slot, 0, Bootstrap_SC_Slot, 1);
   if R /= 0 then return; end if;
   R := Retype_Object (UT, Object_Reply, 0, CNode_Slot, 0, Bootstrap_Reply_Slot, 1);
   if R /= 0 then return; end if;
   R := Retype_Object (UT, Object_Frame, 0, CNode_Slot, 0, Bootstrap_IPC_Frame_Slot, 1);
   if R /= 0 then return; end if;

   R := SchedControl_ConfigureFlags (BI.SchedControl_Start, Bootstrap_SC_Slot,
                                     50_000, 50_000, 0, 0, 0);
   if R /= 0 then return; end if;
   R := SchedContext_Bind (Bootstrap_SC_Slot, Bootstrap_TCB_Slot);
   if R /= 0 then return; end if;
   R := TCB_Set_Timeout_Endpoint (Bootstrap_TCB_Slot, Timeout_EP_Slot);
   if R /= 0 then return; end if;
   R := TCB_Set_Fault_Handler (Bootstrap_TCB_Slot, Root_Fault_EP_Slot,
                               CNode_Slot, 0, Bootstrap_PML4_Slot, 0);
   if R /= 0 then return; end if;
   R := TCB_Set_IPC_Buffer (Bootstrap_TCB_Slot, Bootstrap_IPC_Frame_Slot, 16#500000#);
   if R /= 0 then return; end if;
   R := TCB_Write_Registers (Bootstrap_TCB_Slot, Load_Entry, 16#404018#);
   if R /= 0 then return; end if;
   R := TCB_Resume (Bootstrap_TCB_Slot);
   if R /= 0 then return; end if;
   Debug_Put (83);  -- 'S': Resume OK
end Schild_Bootstrap;
