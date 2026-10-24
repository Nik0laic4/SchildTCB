pragma Spark_Mode (On);

package body Schild_Syscall_Mmu_Switcher is

   procedure Validate_Mmu_Context_Switch
     (Old_Cr3_Val : in     Page_Directory_Register;
      New_Cr3_Val : in     Page_Directory_Register;
      Is_Allowed  :    out Boolean)
   is
      Old_Valid   : Boolean;
      New_Valid   : Boolean;
      Aligned_4K  : Boolean;
      Distinct    : Boolean;
   begin
      Old_Valid  := Old_Cr3_Val >= MIN_PML4_PHYS_ADDR;
      New_Valid  := New_Cr3_Val >= MIN_PML4_PHYS_ADDR;
      Aligned_4K := (New_Cr3_Val and 16#0FFF#) = 0;
      Distinct   := Old_Cr3_Val /= New_Cr3_Val;

      Is_Allowed := Old_Valid and New_Valid and Aligned_4K and Distinct;
   end Validate_Mmu_Context_Switch;

end Schild_Syscall_Mmu_Switcher;
