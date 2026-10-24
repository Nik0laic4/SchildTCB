pragma Spark_Mode (On);

package Schild_Ipc_Queue_Guard is

   --  Fixed-size IPC queue (16 slots).
   QUEUE_SIZE : constant := 16;
   
   type Queue_Index is range 0 .. QUEUE_SIZE - 1;
   type Counter_Type is mod 2**64;

   --  Advance the ring index, wrapping at the end.
   function Next_Index (Current : Queue_Index) return Queue_Index
   with
     Global => null,
     Post   => (if Current < QUEUE_SIZE - 1 then Next_Index'Result = Current + 1
                else Next_Index'Result = 0);

   --  The queue is valid when not full (head != next(tail)).
   procedure Check_Overflow_Invariant
     (Head  : in     Queue_Index;
      Tail  : in     Queue_Index;
      Count : in     Counter_Type;
      Valid :    out Boolean)
   with
     Global => null,
     Depends => (Valid => (Head, Tail, Count)),
     Post   => (if Valid then Count < QUEUE_SIZE and Head /= Next_Index(Tail)
                else Count >= QUEUE_SIZE or Head = Next_Index(Tail));

end Schild_Ipc_Queue_Guard;
