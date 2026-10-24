pragma Spark_Mode (On);

package body Schild_Pcie_Command_Guard is

   procedure Authorize_Bus_Master
     (Has_Valid_Passport : in     Boolean;
      New_Command_Reg    : in     Command_Register_16;
      Is_Auth_Valid      :    out Boolean)
   is
   begin
      --  Bus mastering needs a valid passport and the enable bit set.
      Is_Auth_Valid := (Has_Valid_Passport = True and then 
                        (New_Command_Reg and PCI_COMMAND_BUS_MASTER) /= 0);
   end Authorize_Bus_Master;

end Schild_Pcie_Command_Guard;
