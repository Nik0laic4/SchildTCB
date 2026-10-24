pragma Spark_Mode (On);

package body Schild_Gdt_Core is

   procedure Sanitize_Gdt_Segments
     (Table    : in     Gdt_Matrix;
      Index    : in     Gdt_Table_Index;
      Is_Valid :    out Boolean)
   is
   begin
      if (Table(Index).Access_Byte and 16#60#) = 16#60# then
         Is_Valid := ((Table(Index).Access_Byte and 16#04#) = 0);
      else
         Is_Valid := False;
      end if;
   end Sanitize_Gdt_Segments;

end Schild_Gdt_Core;
