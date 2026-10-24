pragma Spark_Mode (On);

with Interfaces;
use Interfaces;

package body Schild_Net_Parser is

   procedure Parse_Header
     (Frame         : in     Network_Frame_Buffer;
      Ether_Type    :    out Unsigned_16;
      IP_Header_Len :    out Natural;
      IP_Total_Len  :    out Natural;
      Is_Valid      :    out Boolean)
   is
      --  Work from the first byte of the frame buffer.
      F : constant Frame_Index_Type := Frame'First;
   begin
      --  Read the two-byte EtherType at offset 12 (big-endian).
      Ether_Type := Interfaces.Shift_Left(Interfaces.Unsigned_16(Frame(F + 12)), 8) or
                    Interfaces.Unsigned_16(Frame(F + 13));

      if Ether_Type = 16#0800# then
         --  IPv4 header length = low nibble of byte 14, in 4-byte units.
         IP_Header_Len := Natural(Frame(F + 14) and 16#0F#) * 4;
         
         --  IPv4 total length (big-endian) at offset 16.
         IP_Total_Len := Natural(Interfaces.Shift_Left(Interfaces.Unsigned_16(Frame(F + 16)), 8) or
                                 Interfaces.Unsigned_16(Frame(F + 17)));
         Is_Valid := True;
      else
         IP_Header_Len := 0;
         IP_Total_Len  := 0;
         Is_Valid      := False;
      end if;
   end Parse_Header;

end Schild_Net_Parser;
