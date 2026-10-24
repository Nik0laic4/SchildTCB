package body Schild_Linker with
  SPARK_Mode => On
is

   ----------------------
   -- Verify_Multiboot --
   ----------------------
   procedure Verify_Multiboot (Header : Multiboot_Header_Type) is
   begin
      --  Verify the multiboot magic; otherwise nothing is written.
      if Header.Magic_Number = 16#1BADB002# then
         null; --  Magic matches.
      end if;
   end Verify_Multiboot;

end Schild_Linker;
