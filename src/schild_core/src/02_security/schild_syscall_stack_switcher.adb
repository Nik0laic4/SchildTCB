pragma Spark_Mode (On);

package body Schild_Syscall_Stack_Switcher is

   procedure Validate_Stack_Switch
     (Target_Rsp : in     Stack_Pointer_64;
      Is_Secure  :    out Boolean)
   is
      Bounds_OK  : Boolean;
      Aligned_16 : Boolean;
   begin
      Bounds_OK  := (Target_Rsp >= KERNEL_STACK_MIN) and (Target_Rsp <= KERNEL_STACK_MAX);
      Aligned_16 := (Target_Rsp and 16#0F#) = 0;

      Is_Secure  := Bounds_OK and Aligned_16;
   end Validate_Stack_Switch;

end Schild_Syscall_Stack_Switcher;
