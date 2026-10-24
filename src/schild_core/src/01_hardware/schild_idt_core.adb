pragma Spark_Mode (On);

with Interfaces;
use Interfaces;

package body Schild_Idt_Core is

   procedure Validate_Idt_Gate
     (Table    : in     Idt_Gate_Matrix;
      Vector   : in     Idt_Vector_Index;
      Dpl_Level: in     Unsigned_8;
      Is_Valid :    out Boolean)
   is
   begin
      --  The gate must be present and DPL 0..3.
      if Dpl_Level <= 3 and then (Table (Vector).Attributes and 16#80#) = 16#80# then
         Is_Valid := (Table (Vector).Selector = 16#0008#);
      else
         Is_Valid := False;
      end if;
   end Validate_Idt_Gate;

end Schild_Idt_Core;
