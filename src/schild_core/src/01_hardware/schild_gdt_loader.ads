pragma Spark_Mode (On);

with Interfaces;
use Interfaces; --  Unsigned types for GDT entries.

package Schild_Gdt_Loader is

   type Gdt_Pointer_Record is record
      Table_Limit  : Unsigned_16;
      Base_Address : Unsigned_64;
   end record;

   procedure Load_Gdt_Registry
     (Pointer : in     Gdt_Pointer_Record;
      Success :    out Boolean)
   with
     Global => null,
     Pre    => Pointer.Base_Address /= 0 and then Pointer.Table_Limit = 55,
     Post   => (if Success then Pointer.Table_Limit = 55 and Pointer.Base_Address /= 0);

end Schild_Gdt_Loader;
