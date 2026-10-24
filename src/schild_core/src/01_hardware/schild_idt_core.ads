pragma Spark_Mode (On);

with Interfaces;
use Interfaces;

package Schild_Idt_Core is

   type Idt_Vector_Index is range 0 .. 255;

   type Idt_Gate_Entry is record
      Selector   : Unsigned_16;
      Attributes : Unsigned_8;
   end record;

   type Idt_Gate_Matrix is array (Idt_Vector_Index) of Idt_Gate_Entry;

   --  Alias for the IDT vector index.
   subtype Idt_Vector_Range is Idt_Vector_Index;
   subtype Idt_Table_Type is Idt_Gate_Matrix;

   procedure Validate_Idt_Gate
     (Table    : in     Idt_Gate_Matrix;
      Vector   : in     Idt_Vector_Index;
      Dpl_Level: in     Unsigned_8;
      Is_Valid :    out Boolean)
   with
     Global => null,
     Pre    => Dpl_Level <= 3,
     Post   => Is_Valid = ((Table (Vector).Attributes and 16#80#) = 16#80#
                            and Table (Vector).Selector = 16#0008#);

end Schild_Idt_Core;
