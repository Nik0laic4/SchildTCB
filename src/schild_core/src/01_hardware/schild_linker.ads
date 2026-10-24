package Schild_Linker with
  SPARK_Mode => On
is

   --  The multiboot header embedded in the kernel image.
   type Multiboot_Header_Type is record
      Magic_Number : Long_Integer;
      Flags        : Long_Integer;
      Checksum     : Long_Integer;
   end record;

   --  Validate the multiboot magic number (exported to C).
   procedure Verify_Multiboot (Header : Multiboot_Header_Type)
   with
     Export        => True,
     Convention    => C,
     External_Name => "Verify_Multiboot",
     --  Only the multiboot magic is required here; flags and checksum are
     --  validated elsewhere in the boot path.
     Pre           => Header.Magic_Number = 16#1BADB002#;

end Schild_Linker;
