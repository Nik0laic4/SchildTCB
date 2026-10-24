pragma Spark_Mode (On);

package Schild_Pic_Disabler is

   type Pic_Mask_Type is mod 2**8;

   --  Masking all IRQ lines.
   FULL_DISABLE_MASK : constant Pic_Mask_Type := 16#FF#;

   --  Confirm the PIC is fully masked.
   procedure Verify_Pic_Isolation
     (Master_Mask       : in     Pic_Mask_Type;
      Slave_Mask        : in     Pic_Mask_Type;
      Is_Legacy_Isolated:    out Boolean)
   with
     Global  => null,
     Depends => (Is_Legacy_Isolated => (Master_Mask, Slave_Mask)),
     Post    => (if Is_Legacy_Isolated then
                   Master_Mask = FULL_DISABLE_MASK and
                   Slave_Mask = FULL_DISABLE_MASK
                 else
                   Master_Mask /= FULL_DISABLE_MASK or
                   Slave_Mask /= FULL_DISABLE_MASK);

end Schild_Pic_Disabler;
