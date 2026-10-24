pragma Spark_Mode (On);

with Interfaces;
use Interfaces;

package Schild_Stack_Guard is

   type Stack_Pointer_64 is mod 2**64;

   --  Kernel stacks live above 1 MB.
   KERNEL_STACK_LIMIT : constant Stack_Pointer_64 := 16#0000_0000_0010_0000#;

   procedure Verify_Stack_Pointer
     (Current_Rsp : in     Stack_Pointer_64;
      Is_Safe     :    out Boolean)
   with
     Global => null,
     Post   => Is_Safe = (Current_Rsp >= KERNEL_STACK_LIMIT and then (Current_Rsp and 16#7#) = 0);

end Schild_Stack_Guard;
