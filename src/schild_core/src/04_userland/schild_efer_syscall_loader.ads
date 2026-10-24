pragma Spark_Mode (On);

package Schild_Efer_Syscall_Loader is

   type Efer_Register_64 is mod 2**64;

   --  EFER bit masks for syscall (SCE), long-mode enable (LME) and active (LMA).
   EFER_SCE_BIT : constant Efer_Register_64 := 16#0000_0001#; -- System Call Enable
   EFER_LME_BIT : constant Efer_Register_64 := 16#0000_0100#; -- Long Mode Enable
   EFER_LMA_BIT : constant Efer_Register_64 := 16#0000_0400#; -- Long Mode Active

   --  Check that enabling SCE keeps the LME/LMA bits unchanged.
   procedure Validate_Efer_Transition
     (Old_Efer : in     Efer_Register_64;
      New_Efer : in     Efer_Register_64;
      Is_Valid :    out Boolean)
   with
     Global  => null,
     Depends => (Is_Valid => (Old_Efer, New_Efer)),
     Post    => (if Is_Valid then
                   (New_Efer and EFER_SCE_BIT) /= 0 and          --  SCE must be set.
                   (New_Efer and EFER_LME_BIT) = (Old_Efer and EFER_LME_BIT) and --  LME unchanged.
                   (New_Efer and EFER_LMA_BIT) = (Old_Efer and EFER_LMA_BIT)     --  LMA unchanged.
                 else
                   (New_Efer and EFER_SCE_BIT) = 0 or
                   (New_Efer and EFER_LME_BIT) /= (Old_Efer and EFER_LME_BIT) or
                   (New_Efer and EFER_LMA_BIT) /= (Old_Efer and EFER_LMA_BIT));

end Schild_Efer_Syscall_Loader;
