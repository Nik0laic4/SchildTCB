pragma Spark_Mode (On);

package Schild_Pcie_Enumeration_Guard is

   type Pcie_ID_Type is mod 2**16;

   --  Sentinel for absent/empty PCI IDs.
   INVALID_PCIE_ID : constant Pcie_ID_Type := 16#FFFF#;

   --  A device is valid with a non-zero, non-sentinel vendor ID.
   procedure Validate_Device_Identity
     (Vendor_ID       : in     Pcie_ID_Type;
      Device_ID       : in     Pcie_ID_Type;
      Is_Device_Valid :    out Boolean)
   with
     Global  => null,
     Depends => (Is_Device_Valid => (Vendor_ID, Device_ID)),
     Post    => Is_Device_Valid = (Vendor_ID /= INVALID_PCIE_ID and
                                   Vendor_ID >= 1 and
                                   Vendor_ID <= 16#FFFE# and
                                   Device_ID /= INVALID_PCIE_ID);

end Schild_Pcie_Enumeration_Guard;
