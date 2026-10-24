-- Schild TCB Network Filter — body (stub)
--  Stateful inspection stub: drops packets with a zero address.

with Schild_Uart_Driver;

package body Schild_Net_Filter with
  SPARK_Mode => On
is

   procedure Inspect_Stateful_Session
     (Packet : in out Network_Packet_Record;
      Action :    out Filter_Action_Type)
   is
   begin
      Packet.Is_Inspected := True;
      if Packet.Source_IP = 0 or else Packet.Dest_IP = 0 then
         Action := Drop;
      else
         Action := Allow;
      end if;
   end Inspect_Stateful_Session;

end Schild_Net_Filter;