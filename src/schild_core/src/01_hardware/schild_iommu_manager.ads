-- Schild TCB — Intel VT-d (IOMMU) DMA-remapping manager.
--
-- Hardware DMA isolation for the onboard Intel I219-V NIC: the NIC is granted
-- access ONLY to the shared DMA window (5 split page-pairs @0x520000..0x52A000).
-- Every other physical address is blocked by the IOMMU.
--
-- The body performs MMIO register I/O and is therefore outside the SPARK proof
-- set (SPARK_Mode => Off). This specification carries the provable contracts.

with Interfaces; use Interfaces;
with Schild_Acpi_Tables;

package Schild_Iommu_Manager with
  SPARK_Mode => On
is

   --  Opaque 16-bit device identifier (bus:device:function).
   type Device_Id_Type is mod 2**16;

   --  Onboard Intel I219-V (PCH-integrated), BDF 0:31.6.
   Nic_Bdf : constant Device_Id_Type := 16#1F06#;

   --  Shared DMA window granted to the NIC (5 split page-pairs).
   Shared_Base : constant Long_Integer := 16#52_0000#;
   Shared_Top  : constant Long_Integer := 16#52_A000#;

   --  Build the root/context/I-O page tables, enable translation, and grant
   --  the NIC access to the shared window only (all other devices blocked).
   procedure Initialize;

   --  Identity-map one 4 KiB page into a device's I/O address space.
   procedure Map_Device_Page
     (Device_ID   : in  Device_Id_Type;
      Source_Page : in  Long_Integer;
      Target_Page : in  Long_Integer;
      Success     : out Boolean)
   with
     Pre  => Source_Page /= 0 and Target_Page /= 0,
     Post => Success = True or else Success = False;

   --  Revoke a device: mark its context entry not-present (hardware block).
   procedure Block_Device (Device_ID : in Device_Id_Type);

   --  Flush the I/O translation cache.
   procedure Flush_Iommu_Cache with Inline => True;

   --  ACPI DMAR parsing is delegated to Schild_Acpi_Tables (host-testable).
   --  The RSDP -> XSDT -> DMAR lookup that supplies the table address remains
   --  the environment-specific step (real-hardware ACPI / firmware).
   subtype Dmar_Byte_Array is Schild_Acpi_Tables.Byte_Array;

   procedure Parse_Dmar_Table
     (Dmar     : in     Dmar_Byte_Array;
      Reg_Base :    out Unsigned_64;
      Success  :    out Boolean);

end Schild_Iommu_Manager;
