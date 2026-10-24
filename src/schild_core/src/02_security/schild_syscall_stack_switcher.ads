pragma Spark_Mode (On);

package Schild_Syscall_Stack_Switcher is

   type Stack_Pointer_64 is mod 2**64;

   --  Kernel stack window (8..9 MB) used for syscall entry.
   KERNEL_STACK_MIN : constant Stack_Pointer_64 := 16#0000_0000_0080_0000#; -- 8 MB
   KERNEL_STACK_MAX : constant Stack_Pointer_64 := 16#0000_0000_0090_0000#; -- 9 MB

   --  A switch is safe only within the kernel stack window, 16-byte aligned.
   procedure Validate_Stack_Switch
     (Target_Rsp : in     Stack_Pointer_64;
      Is_Secure  :    out Boolean)
   with
     Global  => null,
     Depends => (Is_Secure => Target_Rsp),
     Post    => (if Is_Secure then
                   Target_Rsp >= KERNEL_STACK_MIN and
                   Target_Rsp <= KERNEL_STACK_MAX and
                   (Target_Rsp and 16#0F#) = 0 --  16-byte aligned.
                 else
                   Target_Rsp < KERNEL_STACK_MIN or
                   Target_Rsp > KERNEL_STACK_MAX or
                   (Target_Rsp and 16#0F#) /= 0);

end Schild_Syscall_Stack_Switcher;
