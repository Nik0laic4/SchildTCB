pragma Spark_Mode (On);

package Schild_Pcie_Aer_Guard is

   type Aer_Mask_32 is mod 2**32;

   --  Fatal-error bits that must always be unmasked.
   FATAL_ERRORS_MASK : constant Aer_Mask_32 := 16#0004_1001#;

   --  The mask is safe when fatal errors stay unmasked.
   procedure Validate_Aer_Mask
     (New_Mask_Reg : in     Aer_Mask_32;
      Is_Mask_Safe :    out Boolean)
   with
     Global  => null,
     Depends => (Is_Mask_Safe => New_Mask_Reg),
     Post    => Is_Mask_Safe = ((New_Mask_Reg and FATAL_ERRORS_MASK) = FATAL_ERRORS_MASK);

end Schild_Pcie_Aer_Guard;
