with Interfaces; use Interfaces;

package Schild_Net_Queue with
  SPARK_Mode => On
is

   type Queue_Index_Type is new Interfaces.Unsigned_32 range 0 .. 1024;
   
   type Network_Queue_Record is record
      Head        : Queue_Index_Type := 0;
      Tail        : Queue_Index_Type := 0;
      Is_Full     : Boolean := False;
   end record;

   procedure Enqueue_Packet
     (Queue   : in out Network_Queue_Record;
      Success :    out Boolean)
   with Pre => not Queue.Is_Full,
        Post => (if Success then Queue.Head /= Queue.Tail or Queue.Is_Full);

end Schild_Net_Queue;
