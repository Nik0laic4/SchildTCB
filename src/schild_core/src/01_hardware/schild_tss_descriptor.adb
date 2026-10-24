pragma Spark_Mode (On);

package body Schild_Tss_Descriptor is

   procedure Validate_Tss_Entry
     (Tss_Addr   : in     Interfaces.Unsigned_64;
      Tss_Size   : in     Interfaces.Unsigned_32;
      Table      : in     Tss_Table_Array;
      Is_Success :    out Boolean)
   is
   begin
      if Tss_Addr /= 0 and then Tss_Size >= 104 then
         Is_Success := ((Table(5) and 16#8F#) = 16#89#);
      else
         Is_Success := False;
      end if;
   end Validate_Tss_Entry;

end Schild_Tss_Descriptor;
