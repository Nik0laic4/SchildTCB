package body Schild_Multiboot_Check with
  SPARK_Mode => Off
is

   -------------------------
   -- Audit_Binary_Layout --
   -------------------------
   procedure Audit_Binary_Layout
     (Magic       : in Long_Integer;
      Flags       : in Long_Integer;
      Checksum    : in Long_Integer;
      File_Offset : in Natural;
      Result      : out Validation_Result_Type)
   is
   begin
      Result := (Magic_Ok => False, Checksum_Ok => False, Offset_Valid => False);

      --  The multiboot header must lie within the first 8 KiB of the image.
      if File_Offset <= 8192 then
         Result.Offset_Valid := True;

         --  Check the multiboot magic value (0x1BADB002).
         if Magic = 16#1BADB002# then
            Result.Magic_Ok := True;

            --  The multiboot spec requires magic + flags + checksum == 0.
            --  (Only the low word is checked in this scaffold.)
            if Magic + Flags + Checksum = 0 then
               Result.Checksum_Ok := True;
            end if;
         end if;
      end if;
   end Audit_Binary_Layout;

end Schild_Multiboot_Check;
