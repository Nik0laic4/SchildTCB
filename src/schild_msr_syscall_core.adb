pragma Spark_Mode (On);

package body Schild_Msr_Syscall_Core is

   procedure Validate_Syscall_Msr_Context
     (Lstar_Address : in     Msr_Register_64;
      Fmask_Value   : in     Msr_Register_64;
      Is_Safe       :    out Boolean)
   is
   begin
      --  LSTAR must be set and FMASK must match.
      if Lstar_Address /= 0 and Fmask_Value = REQUIRED_FMASK then
         Is_Safe := True;
      else
         Is_Safe := False;
      end if;
   end Validate_Syscall_Msr_Context;

end Schild_Msr_Syscall_Core;
