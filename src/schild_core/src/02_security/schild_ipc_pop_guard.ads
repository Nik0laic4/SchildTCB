pragma Spark_Mode (On);

package Schild_Ipc_Pop_Guard is

   --  Fixed-size IPC queue (16 slots).
   QUEUE_SIZE : constant := 16;
   
   type Queue_Index is range 0 .. QUEUE_SIZE - 1;
   type Counter_Type is mod 2**64;

   --  Extraction is valid only when the queue is non-empty.
   procedure Check_Underflow_Invariant
     (Head        : in     Queue_Index;
      Tail        : in     Queue_Index;
      Count       : in     Counter_Type;
      Can_Extract :    out Boolean)
   with
     Global => null,
     Depends => (Can_Extract => (Head, Tail, Count)),
     Post   => (if Can_Extract then Count > 0 and Head /= Tail
                else Count = 0 or Head = Tail);

end Schild_Ipc_Pop_Guard;
