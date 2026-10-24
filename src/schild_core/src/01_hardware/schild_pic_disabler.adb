pragma Spark_Mode (On);

package body Schild_Pic_Disabler is

   procedure Verify_Pic_Isolation
     (Master_Mask       : in     Pic_Mask_Type;
      Slave_Mask        : in     Pic_Mask_Type;
      Is_Legacy_Isolated:    out Boolean)
   is
   begin
      --  Isolation holds when both PICs are fully masked.
      if Master_Mask = FULL_DISABLE_MASK and Slave_Mask = FULL_DISABLE_MASK then
         Is_Legacy_Isolated := True;
      else
         Is_Legacy_Isolated := False;
      end if;
   end Verify_Pic_Isolation;

end Schild_Pic_Disabler;
