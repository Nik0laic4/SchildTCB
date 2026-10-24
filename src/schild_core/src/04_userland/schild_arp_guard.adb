pragma Spark_Mode (On);

package body Schild_Arp_Guard is

   procedure Update_Arp_Cache
     (Index   : in     Arp_Table_Index;
      New_Mac : in     Mac_Address_Array;
      Table   : in out Arp_Cache_Matrix;
      Success :    out Boolean)
   is
   begin
      if Table (Index).Is_Valid then
         Table (Index).MAC_Addr := New_Mac;
         Success                := True;
      else
         Success                := False;
      end if;
   end Update_Arp_Cache;

end Schild_Arp_Guard;
