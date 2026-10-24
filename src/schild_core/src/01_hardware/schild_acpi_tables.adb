package body Schild_Acpi_Tables
  with SPARK_Mode => Off  --  parser bounds/bit-twiddling: validated by host KAT.
is

   procedure Parse_Rsdp
     (Rsdp      : in     Byte_Array;
      Xsdt_Addr :    out Unsigned_64;
      Success   :    out Boolean)
   is
   begin
      Success := False;
      Xsdt_Addr := 0;

      --  RSDP is at least 36 bytes (ACPI >= 2.0).
      if Rsdp'Length < 36 then
         return;
      end if;
      --  Signature "RSD PTR " (8 bytes).
      if Rsdp (Rsdp'First + 0) /= 16#52# or Rsdp (Rsdp'First + 1) /= 16#53#
        or Rsdp (Rsdp'First + 2) /= 16#44# or Rsdp (Rsdp'First + 3) /= 16#20#
        or Rsdp (Rsdp'First + 4) /= 16#50# or Rsdp (Rsdp'First + 5) /= 16#54#
        or Rsdp (Rsdp'First + 6) /= 16#52# or Rsdp (Rsdp'First + 7) /= 16#20#
      then
         return;
      end if;
      --  Revision at offset 15; XsdtAddress is only valid for revision >= 2.
      if Rsdp (Rsdp'First + 15) < 2 then
         return;
      end if;
      --  XsdtAddress: 8 bytes little-endian at offset 24.
      for I in 0 .. 7 loop
         Xsdt_Addr := Xsdt_Addr
           or Shift_Left (Unsigned_64 (Rsdp (Rsdp'First + 24 + I)), 8 * I);
      end loop;
      Success := True;
   end Parse_Rsdp;

   procedure Parse_Xsdt_Header
     (Xsdt        : in     Byte_Array;
      Table_Count :    out Natural;
      Success     :    out Boolean)
   is
      Len : Unsigned_32 := 0;
   begin
      Success := False;
      Table_Count := 0;

      if Xsdt'Length < 36 then
         return;
      end if;
      --  Signature "XSDT" (4 bytes).
      if Xsdt (Xsdt'First + 0) /= 16#58# or Xsdt (Xsdt'First + 1) /= 16#53#
        or Xsdt (Xsdt'First + 2) /= 16#44# or Xsdt (Xsdt'First + 3) /= 16#54#
      then
         return;
      end if;
      --  Length: 4 bytes little-endian at offset 4.
      for I in 0 .. 3 loop
         Len := Len
           or Shift_Left (Unsigned_32 (Xsdt (Xsdt'First + 4 + I)), 8 * I);
      end loop;
      if Len < 36 or Unsigned_32 (Xsdt'Length) < Len then
         return;
      end if;
      Table_Count := Natural ((Len - 36) / 8);
      Success := True;
   end Parse_Xsdt_Header;

   procedure Parse_Dmar_Table
     (Dmar     : in     Byte_Array;
      Reg_Base :    out Unsigned_64;
      Success  :    out Boolean)
   is
      Off   : Natural;
      Len   : Natural;
      Stype : Unsigned_16;
      SLen  : Natural;
   begin
      Success := False;
      Reg_Base := 0;

      if Dmar'Length < 36 then
         return;
      end if;
      --  ACPI SDT header: signature "DMAR".
      if Dmar (Dmar'First) /= 16#44# or Dmar (Dmar'First + 1) /= 16#4D#
        or Dmar (Dmar'First + 2) /= 16#41# or Dmar (Dmar'First + 3) /= 16#52#
      then
         return;  --  not a DMAR table
      end if;
      Len := Natural (Unsigned_32 (Dmar (Dmar'First + 4))
             or Shift_Left (Unsigned_32 (Dmar (Dmar'First + 5)), 8)
             or Shift_Left (Unsigned_32 (Dmar (Dmar'First + 6)), 16)
             or Shift_Left (Unsigned_32 (Dmar (Dmar'First + 7)), 24));
      if Len > Dmar'Length then
         Len := Dmar'Length;
      end if;

      --  DMA-remapping structures start after the 36-byte SDT header AND the
      --  12-byte DMAR-specific header (host address width + flags + reserved).
      Off := Dmar'First + 48;
      while Off + 4 <= Dmar'First + Len loop
         Stype := Unsigned_16 (Dmar (Off))
                  or Shift_Left (Unsigned_16 (Dmar (Off + 1)), 8);
         if Stype = 0 then
            --  DRHD: register base address is 8 bytes little-endian at
            --  structure offset +8 (after type/length/flags/reserved/segment).
            if Off + 16 <= Dmar'First + Len then
               Reg_Base := Unsigned_64 (Dmar (Off + 8))
                 or Shift_Left (Unsigned_64 (Dmar (Off + 9)), 8)
                 or Shift_Left (Unsigned_64 (Dmar (Off + 10)), 16)
                 or Shift_Left (Unsigned_64 (Dmar (Off + 11)), 24)
                 or Shift_Left (Unsigned_64 (Dmar (Off + 12)), 32)
                 or Shift_Left (Unsigned_64 (Dmar (Off + 13)), 40)
                 or Shift_Left (Unsigned_64 (Dmar (Off + 14)), 48)
                 or Shift_Left (Unsigned_64 (Dmar (Off + 15)), 56);
               Success := True;
            end if;
            return;
         end if;
         --  Advance by this structure's length (2 bytes at offset +2).
         SLen := Natural (Unsigned_32 (Dmar (Off + 2))
                 or Shift_Left (Unsigned_32 (Dmar (Off + 3)), 8));
         if SLen = 0 then
            SLen := 1;  --  avoid an infinite loop on a malformed table
         end if;
         Off := Off + SLen;
      end loop;
   end Parse_Dmar_Table;

end Schild_Acpi_Tables;
