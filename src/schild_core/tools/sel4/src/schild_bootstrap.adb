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

   BI : Schild_Sel4_BootInfo.BootInfo;
   R : Unsigned_64;
   Load_Status : Unsigned_64;
   Load_Entry  : Unsigned_64;
   UT : Cap_Ref := 0;
   CNode_Slot : constant Cap_Ref := 1;
   Root_VSpace : constant Cap_Ref := 3;
begin
   Get_BootInfo_Copy (BI, Unsigned_64 (Schild_Sel4_BootInfo.BootInfo'Size / System.Storage_Unit));

   -- Find a RAM untyped for the root task's VSpace objects + image frames.
   for I in BI.Untyped_List'Range loop
      if BI.Untyped_List (I).Size_Bits >= 18
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

   -- Phase B next: retype TCB + SC + Reply, TCB_Set_Space + Write_Registers +
   -- TCB_Resume (entry = Load_Entry). Skeleton for now.
   null;
end Schild_Bootstrap;
