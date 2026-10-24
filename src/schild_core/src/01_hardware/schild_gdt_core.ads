pragma Spark_Mode (On);

with Interfaces; 
use Interfaces;

package Schild_Gdt_Core is

   type Gdt_Table_Index is range 1 .. 8;
   
   type Gdt_Entry_Record is record
      Access_Byte : Unsigned_8;
      Base_High   : Unsigned_8;
   end record;

   type Gdt_Matrix is array (Gdt_Table_Index) of Gdt_Entry_Record;
   
   subtype Gdt_Table_Type is Gdt_Matrix;

   procedure Sanitize_Gdt_Segments
     (Table    : in     Gdt_Matrix;
      Index    : in     Gdt_Table_Index;
      Is_Valid :    out Boolean)
   with
     Global => null,
     Pre    => (Table(Index).Access_Byte and 16#60#) = 16#60#,
     Post   => Is_Valid = ((Table(Index).Access_Byte and 16#04#) = 0);

end Schild_Gdt_Core;
