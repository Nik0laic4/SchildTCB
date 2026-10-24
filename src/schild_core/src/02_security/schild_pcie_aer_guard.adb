pragma Spark_Mode (On);

package body Schild_Pcie_Aer_Guard is

   procedure Validate_Aer_Mask
     (New_Mask_Reg : in     Aer_Mask_32;
      Is_Mask_Safe :    out Boolean)
   is
   begin
      --  Safe when fatal-error bits stay unmasked.
      Is_Mask_Safe := ((New_Mask_Reg and FATAL_ERRORS_MASK) = FATAL_ERRORS_MASK);
   end Validate_Aer_Mask;

end Schild_Pcie_Aer_Guard;
