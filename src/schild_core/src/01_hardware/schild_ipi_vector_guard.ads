with Interfaces; use Interfaces;

package Schild_Ipi_Vector_Guard with
  SPARK_Mode => On
is
   pragma Elaborate_Body;

   --  IPI vectors use the 240..255 range.
   subtype Ipi_Vector_Type is Interfaces.Unsigned_8 range 240 .. 255;

   procedure Validate_Ipi_Vector
     (Vector : in     Interfaces.Unsigned_8;
      Valid  :    out Boolean)
   with Post => (if Valid then Vector in Ipi_Vector_Type);

end Schild_Ipi_Vector_Guard;
