pragma Spark_Mode (On);

with Interfaces; 
use Interfaces;

package Schild_Net_Parser is

   type Frame_Index_Type is range 1 .. 1500;
   
   --  Variable-length frame buffer indexed by frame byte position.
   type Network_Frame_Buffer is array (Frame_Index_Type range <>) of Unsigned_8;
   
   --  Fixed-size (1500-byte) packet buffer.
   type Fixed_Network_Packet is array (Frame_Index_Type) of Unsigned_8;

   type Network_Packet_Passport is record
      Is_Valid_IPv4  : Boolean;
      Payload_Offset : Frame_Index_Type;
      Payload_Length : Natural;
      Icmp_Type      : Unsigned_8;
   end record;

   procedure Parse_Header
     (Frame         : in     Network_Frame_Buffer;
      Ether_Type    :    out Unsigned_16;
      IP_Header_Len :    out Natural;
      IP_Total_Len  :    out Natural;
      Is_Valid      :    out Boolean)
   with
     Global => null,
     Pre    => Frame'Length >= 34,
     Post   => (if Is_Valid then Ether_Type = 16#0800#);

end Schild_Net_Parser;
