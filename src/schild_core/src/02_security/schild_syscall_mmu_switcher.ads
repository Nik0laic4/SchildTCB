pragma Spark_Mode (On);

package Schild_Syscall_Mmu_Switcher is

   type Page_Directory_Register is mod 2**64;

   --  PML4 tables must sit above 1 MB.
   MIN_PML4_PHYS_ADDR : constant Page_Directory_Register := 16#0000_0000_0010_0000#; -- 1 MB

   --  A switch needs two distinct, page-aligned PML4 tables above 1 MB.
   procedure Validate_Mmu_Context_Switch
     (Old_Cr3_Val : in     Page_Directory_Register;
      New_Cr3_Val : in     Page_Directory_Register;
      Is_Allowed  :    out Boolean)
   with
     Global  => null,
     Depends => (Is_Allowed => (Old_Cr3_Val, New_Cr3_Val)),
     Post    => (if Is_Allowed then 
                   Old_Cr3_Val >= MIN_PML4_PHYS_ADDR and
                   New_Cr3_Val >= MIN_PML4_PHYS_ADDR and
                   (New_Cr3_Val and 16#0FFF#) = 0 and --  4 KiB-aligned.
                   Old_Cr3_Val /= New_Cr3_Val
                 else 
                   Old_Cr3_Val < MIN_PML4_PHYS_ADDR or
                   New_Cr3_Val < MIN_PML4_PHYS_ADDR or
                   (New_Cr3_Val and 16#0FFF#) /= 0 or
                   Old_Cr3_Val = New_Cr3_Val);

end Schild_Syscall_Mmu_Switcher;
