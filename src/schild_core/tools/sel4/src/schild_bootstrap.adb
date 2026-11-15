-- Schild TCB — mini-bootstrap (root task as ELF-child, Phase B).
-- First userspace thread. Phase B: read BootInfo, retype a PML4 + page
-- tables, Load_Elf(root_task.elf) into that VSpace, TCB_Resume the root task
-- (ROOT_TASK_ELF_CHILD_DESIGN.md). This is a skeleton — the loader body is
-- added incrementally (B1..B3).
with Schild_Sel4_BootInfo;
with Interfaces; use Interfaces;
with System;

procedure Schild_Bootstrap with SPARK_Mode => Off is
   -- Read the seL4 BootInfo frame as a VALUE via the C memcpy shim (same as
   -- Schild_Root_Task). Phase B uses it to locate the RAM untyped for the
   -- root task's VSpace objects.
   procedure Get_BootInfo_Copy (BI : out Schild_Sel4_BootInfo.BootInfo; Nbytes : Unsigned_64)
     with Import, Convention => C, External_Name => "schild_get_bootinfo_copy",
          Global => null;
   BI : Schild_Sel4_BootInfo.BootInfo;
begin
   Get_BootInfo_Copy (BI, Unsigned_64 (Schild_Sel4_BootInfo.BootInfo'Size / System.Storage_Unit));
   -- Skeleton: BootInfo read; retype + Load_Elf + TCB_Resume follow in B1..B3.
   null;
end Schild_Bootstrap;
