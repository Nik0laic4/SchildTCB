package body Schild_Net_Queue with
  SPARK_Mode => Off --  Circular packet queue (scaffold).
is

   procedure Enqueue_Packet
     (Queue   : in out Network_Queue_Record;
      Success :    out Boolean)
   is
   begin
      --  Append only when the ring is not full.
      if not Queue.Is_Full then
         Queue.Head := (Queue.Head + 1) mod 1025;
         if Queue.Head = Queue.Tail then
            Queue.Is_Full := True;
         end if;
         Success := True;
      else
         Success := False;
      end if;
   end Enqueue_Packet;

end Schild_Net_Queue;
