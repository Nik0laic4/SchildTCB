package body Schild_Ipi_Vector_Guard with
  SPARK_Mode => On
is
   procedure Validate_Ipi_Vector
     (Vector : in     Interfaces.Unsigned_8;
      Valid  :    out Boolean)
   is
   begin
      if Vector >= 240 then
         Valid := True;
      else
         Valid := False;
      end if;
   end Validate_Ipi_Vector;
end Schild_Ipi_Vector_Guard;
