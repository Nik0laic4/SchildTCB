pragma Spark_Mode (On);

package body Schild_Efer_Syscall_Loader is

   procedure Validate_Efer_Transition
     (Old_Efer : in     Efer_Register_64;
      New_Efer : in     Efer_Register_64;
      Is_Valid :    out Boolean)
   is
      SCE_Enabled : Boolean;
      LME_Stable  : Boolean;
      LMA_Stable  : Boolean;
   begin
      SCE_Enabled := (New_Efer and EFER_SCE_BIT) /= 0;
      LME_Stable  := (New_Efer and EFER_LME_BIT) = (Old_Efer and EFER_LME_BIT);
      LMA_Stable  := (New_Efer and EFER_LMA_BIT) = (Old_Efer and EFER_LMA_BIT);

      Is_Valid := SCE_Enabled and LME_Stable and LMA_Stable;
   end Validate_Efer_Transition;

end Schild_Efer_Syscall_Loader;
