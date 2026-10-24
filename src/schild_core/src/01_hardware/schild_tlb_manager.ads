package Schild_TLB_Manager with
  SPARK_Mode => Off
is

   --  Invalidate one page in the TLB.
   procedure Flush_Page (Address : in Long_Integer) with
     Inline => True;

   --  Switch address space (ASID change reloads CR3).
   procedure Switch_Context (Old_ASID : in Positive; New_ASID : in Positive) with
     Pre => Old_ASID /= New_ASID;

end Schild_TLB_Manager;
