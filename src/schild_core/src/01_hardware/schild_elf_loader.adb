package body Schild_Elf_Loader with
  SPARK_Mode => On
is

   -------------------------
   -- Validate_Elf_Header --
   -------------------------
   procedure Validate_Elf_Header
     (Header   : in Elf_Header_Type;
      Is_Valid : out Boolean)
   is
   begin
      Is_Valid := False;

      --  Accept only valid ELF headers.
      if Header.Magic_Valid 
        and then Header.Entry_Point >= 16#0040_0000#
        and then Header.Entry_Point < 16#0000_7FFF_FFFF_F000#
      then
         --  W^X: reject writable+executable segments.
         if not (Header.Is_Writable and Header.Is_Executable) then
            Is_Valid := True;
         end if;
      end if;
   end Validate_Elf_Header;

end Schild_Elf_Loader;
