pragma Spark_Mode (On);

package body Schild_Syscall_Arg_Guard is

   procedure Validate_Syscall_Pointer
     (Arg_Pointer : in     Memory_Address;
      Arg_Length  : in     Memory_Address;
      Is_Trusted  :    out Boolean)
   is
   begin
      --  Trust the pointer only when it fits entirely in user space.
      if Arg_Pointer <= USER_SPACE_MAX_ADDR and then
         Arg_Length <= USER_SPACE_MAX_ADDR and then
         (USER_SPACE_MAX_ADDR - Arg_Pointer) >= Arg_Length
      then
         Is_Trusted := True;
      else
         Is_Trusted := False;
      end if;
   end Validate_Syscall_Pointer;

end Schild_Syscall_Arg_Guard;
