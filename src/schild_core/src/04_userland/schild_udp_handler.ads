with Interfaces; use Interfaces;
with Schild_Net_Filter; use Schild_Net_Filter;

package Schild_Udp_Handler with
  SPARK_Mode => On
is

   type Port_Number_Type is new Interfaces.Unsigned_16;
   
   type Udp_Header_Passport is record
      Source_Port : Port_Number_Type := 0;
      Dest_Port   : Port_Number_Type := 0;
      Length_Ok   : Boolean := False;
   end record;

   procedure Process_Udp_Datagram
     (Raw_Buffer : in     Interfaces.Unsigned_8;
      Packet_Len : in     Schild_Net_Filter.Packet_Length_Type;
      Passport   :    out Udp_Header_Passport;
      Success    :    out Boolean)
   with Pre => Packet_Len >= 8, --  A UDP header is at least 8 bytes.
        Post => (if Success then Passport.Length_Ok);

end Schild_Udp_Handler;
