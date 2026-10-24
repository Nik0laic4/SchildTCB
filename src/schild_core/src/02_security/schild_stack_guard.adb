pragma Spark_Mode (On);

package body Schild_Stack_Guard is

   procedure Verify_Stack_Pointer
     (Current_Rsp : in     Stack_Pointer_64;
      Is_Safe     :    out Boolean)
   is
   begin
      --  Safe when above the limit and 8-byte aligned.
      Is_Safe := (Current_Rsp >= KERNEL_STACK_LIMIT and then (Current_Rsp and 16#7#) = 0);
   end Verify_Stack_Pointer;

end Schild_Stack_Guard;
