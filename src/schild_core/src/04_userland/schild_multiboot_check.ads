package Schild_Multiboot_Check with
  SPARK_Mode => Off
is
   pragma Elaborate_Body;

   type Validation_Result_Type is record
      Offset_Valid : Boolean := False;
      Magic_Ok     : Boolean := False;
      Checksum_Ok  : Boolean := False;
   end record;

end Schild_Multiboot_Check;
