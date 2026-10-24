pragma Spark_Mode (On);
pragma Unevaluated_Use_Of_Old (Allow);

with Interfaces;
use Interfaces;

package Schild_Arp_Guard is

   type Arp_Table_Index is range 1 .. 32;
   type Mac_Address_Array is array (1 .. 6) of Unsigned_8;

   --  IPv4 addresses are stored as 32-bit words.
   subtype Ipv4_Address_Type is Unsigned_32;

   type Arp_Entry_Record is record
      IP_Addr  : Unsigned_32;
      MAC_Addr : Mac_Address_Array;
      Is_Valid : Boolean;
   end record;

   type Arp_Cache_Matrix is array (Arp_Table_Index) of Arp_Entry_Record;

   procedure Update_Arp_Cache
     (Index   : in     Arp_Table_Index;
      New_Mac : in     Mac_Address_Array;
      Table   : in out Arp_Cache_Matrix;
      Success :    out Boolean)
   with
     Global => null,
     Post   => (if not Success then Table (Index).MAC_Addr = Table (Index).MAC_Addr'Old);

end Schild_Arp_Guard;
