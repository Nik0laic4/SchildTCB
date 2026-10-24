pragma Spark_Mode (On);

package body Schild_Ipc_Queue_Guard is

   function Next_Index (Current : Queue_Index) return Queue_Index is
   begin
      if Current < QUEUE_SIZE - 1 then
         return Current + 1;
      else
         return 0;
      end if;
   end Next_Index;

   procedure Check_Overflow_Invariant
     (Head  : in     Queue_Index;
      Tail  : in     Queue_Index;
      Count : in     Counter_Type;
      Valid :    out Boolean)
   is
      Next : Queue_Index;
   begin
      Next  := Next_Index(Tail);
      Valid := (Count < QUEUE_SIZE) and (Head /= Next);
   end Check_Overflow_Invariant;

end Schild_Ipc_Queue_Guard;
