pragma Spark_Mode (On);

package body Schild_Ipc_Pop_Guard is

   procedure Check_Underflow_Invariant
     (Head        : in     Queue_Index;
      Tail        : in     Queue_Index;
      Count       : in     Counter_Type;
      Can_Extract :    out Boolean)
   is
   begin
      --  Extract only when the queue is non-empty.
      Can_Extract := (Count > 0) and (Head /= Tail);
   end Check_Underflow_Invariant;

end Schild_Ipc_Pop_Guard;
