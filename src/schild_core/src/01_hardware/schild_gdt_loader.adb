pragma Spark_Mode (On);

with Interfaces;
use Interfaces;

package body Schild_Gdt_Loader is

   procedure Load_Gdt_Registry
     (Pointer : in     Gdt_Pointer_Record;
      Success :    out Boolean)
   is
   begin
      --  The GDT pointer must have a base and the 6-entry limit.
      if Pointer.Base_Address /= 0 and then Pointer.Table_Limit = 55 then
         Success := True;
      else
         Success := False;
      end if;
   end Load_Gdt_Registry;

end Schild_Gdt_Loader;
