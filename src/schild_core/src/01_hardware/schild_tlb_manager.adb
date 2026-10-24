with System.Machine_Code; use System.Machine_Code;

package body Schild_TLB_Manager with
  SPARK_Mode => Off
is

   ----------------
   -- Flush_Page --
   ----------------
   procedure Flush_Page (Address : in Long_Integer) is
   begin
      --  Invalidate a single page (INVLPG).
      Asm (Template => "invlpg (%0)",
           Inputs   => Long_Integer'Asm_Input ("r", Address),
           Volatile => True);
   end Flush_Page;

   --------------------
   -- Switch_Context --
   --------------------
   procedure Switch_Context (Old_ASID : in Positive; New_ASID : in Positive) is
   begin
      --  Reload CR3 only when the address space actually changes.
      if Old_ASID /= New_ASID then
         --  Switch address space by reloading CR3.
         Asm (Template => "mov %0, %%cr3",
              Inputs   => Long_Integer'Asm_Input ("r", Long_Integer(New_ASID)),
              Volatile => True);
      end if;
   end Switch_Context;

end Schild_TLB_Manager;
