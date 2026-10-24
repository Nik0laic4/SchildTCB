package Schild_Elf_Loader with
  SPARK_Mode => On
is

   --  The ELF file header fields we validate.
   type Elf_Header_Type is record
      Magic_Valid  : Boolean;
      Entry_Point  : Long_Integer;
      Code_Size    : Positive;
      Is_Writable  : Boolean;
      Is_Executable: Boolean;
   end record;

   --  Check the ELF magic and layout flags.
   procedure Validate_Elf_Header
     (Header   : in Elf_Header_Type;
      Is_Valid : out Boolean)
   with
     --  Valid headers pass all sanity checks.
     Post => (if Is_Valid then Header.Magic_Valid 
              and Header.Entry_Point >= 16#0040_0000# 
              and not (Header.Is_Writable and Header.Is_Executable));

end Schild_Elf_Loader;
