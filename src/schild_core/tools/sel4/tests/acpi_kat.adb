-- Copyright (C) 2026 Alexander Irganov
-- SPDX-License-Identifier: GPL-2.0-only

-- =============================================================================
-- Known-answer test (KAT) for Schild_Acpi_Tables (RSDP / XSDT / DMAR parsing).
--
--   * RSDP -> 64-bit XsdtAddress (and revision < 2 rejection)
--   * XSDT header -> table-entry count
--   * DMAR -> first DRHD MMIO register base (regression for the +48/+8 offsets)
--
-- Host-side program (native runtime): run via run_acpi_kat.sh. Exits non-zero
-- if any vector mismatches.
-- =============================================================================

with Ada.Command_Line;
with Ada.Text_IO;
with Interfaces;         use Interfaces;
with Schild_Acpi_Tables; use Schild_Acpi_Tables;

procedure Acpi_KAT is

   Failures : Natural := 0;

   function Hex_Val (C : Character) return Unsigned_8 is
   begin
      if C in '0' .. '9' then
         return Unsigned_8 (Character'Pos (C) - Character'Pos ('0'));
      elsif C in 'a' .. 'f' then
         return Unsigned_8 (Character'Pos (C) - Character'Pos ('a') + 10);
      elsif C in 'A' .. 'F' then
         return Unsigned_8 (Character'Pos (C) - Character'Pos ('A') + 10);
      else
         return 0;
      end if;
   end Hex_Val;

   function Hex (S : String) return Byte_Array is
      B : Byte_Array (0 .. S'Length / 2 - 1);
   begin
      for I in B'Range loop
         B (I) := Shift_Left (Hex_Val (S (S'First + 2 * I)), 4)
                  or Hex_Val (S (S'First + 2 * I + 1));
      end loop;
      return B;
   end Hex;

   procedure Report (Name : String; Ok : Boolean) is
   begin
      if Ok then
         Ada.Text_IO.Put_Line ("PASS  " & Name);
      else
         Ada.Text_IO.Put_Line ("FAIL  " & Name);
         Failures := Failures + 1;
      end if;
   end Report;

begin
   --  RSDP (ACPI >= 2.0) -> XsdtAddress = 0xDEADBEEF.
   declare
      Rsdp : constant Byte_Array := Hex
        ("5253442050545220" &   -- "RSD PTR "
         "00" &                 -- checksum
         "000000000000" &       -- OEMID
         "02" &                 -- revision 2
         "00000000" &           -- RsdtAddress (unused for rev >= 2)
         "24000000" &           -- length 36
         "EFBEADDE00000000" &   -- XsdtAddress = 0xDEADBEEF (LE)
         "00" &                 -- extended checksum
         "000000");             -- reserved
      Xsdt : Unsigned_64;
      Ok   : Boolean;
   begin
      Parse_Rsdp (Rsdp, Xsdt, Ok);
      Report ("RSDP -> XsdtAddress 0xDEADBEEF",
              Ok and then Xsdt = 16#DEADBEEF#);
   end;

   --  RSDP revision 1 has no XSDT -> must be rejected.
   declare
      Rsdp : constant Byte_Array := Hex
        ("5253442050545220" & "00" & "000000000000" &
         "01" &                 -- revision 1
         "00000000" & "24000000" & "EFBEADDE00000000" & "00" & "000000");
      Xsdt : Unsigned_64;
      Ok   : Boolean;
   begin
      Parse_Rsdp (Rsdp, Xsdt, Ok);
      Report ("RSDP revision 1 rejected", not Ok);
   end;

   --  XSDT header (52 bytes) -> 2 table entries.
   declare
      Xsdt : constant Byte_Array := Hex
        ("58534454" &           -- "XSDT"
         "34000000" &           -- length 52
         "01" & "00" &          -- revision, checksum
         "000000000000" &       -- OEMID
         "0000000000000000" &   -- OEM table id
         "00000000" & "00000000" & "00000000" &  -- OEM rev / creator / creator rev
         "0000000000000000" & "0000000000000000");  -- 2 entries
      Count : Natural;
      Ok    : Boolean;
   begin
      Parse_Xsdt_Header (Xsdt, Count, Ok);
      Report ("XSDT -> 2 entries", Ok and then Count = 2);
   end;

   --  DMAR (64 bytes) -> first DRHD register base = 0xFED91000.
   --  Regression: structures begin at offset 48 (36 SDT + 12 DMAR header) and
   --  the DRHD register base is at structure offset +8.
   declare
      Dmar : constant Byte_Array := Hex
        ("444D4152" &           -- "DMAR"
         "40000000" &           -- length 64
         "01" & "00" &          -- revision, checksum
         "000000000000" &       -- OEMID
         "0000000000000000" &   -- OEM table id
         "00000000" & "00000000" & "00000000" &  -- OEM rev / creator / creator rev
         "2F" &                 -- host address width
         "00" &                 -- flags
         "00000000000000000000" & -- reserved (10 bytes)
         "0000" &               -- DRHD type 0
         "1000" &               -- DRHD length 16
         "01" & "00" &          -- DRHD flags, reserved
         "0000" &               -- segment
         "0010D9FE00000000");   -- register base = 0xFED91000 (LE)
      Base : Unsigned_64;
      Ok   : Boolean;
   begin
      Parse_Dmar_Table (Dmar, Base, Ok);
      Report ("DMAR -> DRHD base 0xFED91000",
              Ok and then Base = 16#FED91000#);
   end;

   if Failures = 0 then
      Ada.Text_IO.Put_Line ("ACPI KAT: ALL PASS (4 checks)");
   else
      Ada.Text_IO.Put_Line ("ACPI KAT:" & Natural'Image (Failures) & " FAILURE(S)");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Acpi_KAT;
