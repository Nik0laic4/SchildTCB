-- Schild TCB — ACPI table parsing (pure, host-testable).
--
-- Implements the pure parts of the RSDP -> XSDT -> DMAR resolution chain:
--   Parse_Rsdp        : RSDP  -> 64-bit XSDT physical address
--   Parse_Xsdt_Header : XSDT  -> table-entry count
--   Parse_Dmar_Table  : DMAR  -> first DRHD MMIO register base
--
-- The remaining "read the RSDP from physical memory and dereference each XSDT
-- entry signature" is the environment-specific step (real-hardware ACPI /
-- firmware); the parsing logic here is validated by tools/sel4/tests/acpi_kat.adb.

with Interfaces; use Interfaces;

package Schild_Acpi_Tables
  with SPARK_Mode => On
is

   type Byte_Array is array (Natural range <>) of Unsigned_8;

   --  RSDP (ACPI >= 2.0): validate the "RSD PTR " signature and revision >= 2,
   --  then return the 64-bit XsdtAddress (bytes 24..31, little-endian).
   procedure Parse_Rsdp
     (Rsdp      : in     Byte_Array;
      Xsdt_Addr :    out Unsigned_64;
      Success   :    out Boolean);

   --  XSDT header: validate the "XSDT" signature and return the number of
   --  64-bit table entries = (Length - 36) / 8.
   procedure Parse_Xsdt_Header
     (Xsdt        : in     Byte_Array;
      Table_Count :    out Natural;
      Success     :    out Boolean);

   --  DMAR: extract the first DRHD (DMA Remapping Hardware unit) MMIO register
   --  base (8 bytes little-endian at structure offset +8).
   procedure Parse_Dmar_Table
     (Dmar     : in     Byte_Array;
      Reg_Base :    out Unsigned_64;
      Success  :    out Boolean);

end Schild_Acpi_Tables;
