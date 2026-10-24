with Interfaces; use Interfaces;

package Schild_Net_Filter with
  SPARK_Mode => On
is

   type Packet_Length_Type is new Interfaces.Unsigned_32 range 0 .. 65535;
   type Filter_Action_Type is (Drop, Allow, Log_Alert);

   type Network_Packet_Record is record
      Source_IP   : Interfaces.Unsigned_32;
      Dest_IP     : Interfaces.Unsigned_32;
      Payload_Len : Packet_Length_Type;
      Is_Inspected: Boolean := False;
   end record;

   procedure Inspect_Stateful_Session
     (Packet : in out Network_Packet_Record;
      Action :    out Filter_Action_Type)
   with Post => Packet.Is_Inspected;

end Schild_Net_Filter;
