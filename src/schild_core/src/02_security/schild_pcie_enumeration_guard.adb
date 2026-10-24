pragma Spark_Mode (On);

package body Schild_Pcie_Enumeration_Guard is

   procedure Validate_Device_Identity
     (Vendor_ID       : in     Pcie_ID_Type;
      Device_ID       : in     Pcie_ID_Type;
      Is_Device_Valid :    out Boolean)
   is
   begin
      --  A device is present when the vendor ID is real and non-sentinel.
      Is_Device_Valid := (Vendor_ID /= INVALID_PCIE_ID and then
                          Vendor_ID >= 1 and then
                          Vendor_ID <= 16#FFFE# and then
                          Device_ID /= INVALID_PCIE_ID);
   end Validate_Device_Identity;

end Schild_Pcie_Enumeration_Guard;
