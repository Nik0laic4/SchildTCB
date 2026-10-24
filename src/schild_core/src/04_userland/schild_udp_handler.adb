package body Schild_Udp_Handler with
  SPARK_Mode => Off --  Scaffold: reports a fixed DNS (port 53) datagram.
is

   procedure Process_Udp_Datagram
     (Raw_Buffer : in     Interfaces.Unsigned_8;
      Packet_Len : in     Schild_Net_Filter.Packet_Length_Type;
      Passport   :    out Udp_Header_Passport;
      Success    :    out Boolean)
   is
   begin
      --  Scaffold: hard-code a DNS response datagram.
      Passport.Source_Port := 53; --  DNS well-known port.
      Passport.Dest_Port   := 53;
      Passport.Length_Ok   := True;
      Success              := True;
   end Process_Udp_Datagram;

end Schild_Udp_Handler;
