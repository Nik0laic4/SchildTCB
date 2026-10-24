pragma Spark_Mode (On);

package Schild_Pcie_Command_Guard is

   type Command_Register_16 is mod 2**16;

   --  Bus-master-enable bit of the PCI command register.
   PCI_COMMAND_BUS_MASTER : constant Command_Register_16 := 16#0004#;

   --  Bus mastering is allowed only with a valid passport.
   procedure Authorize_Bus_Master
     (Has_Valid_Passport : in     Boolean;
      New_Command_Reg    : in     Command_Register_16;
      Is_Auth_Valid      :    out Boolean)
   with
     Global  => null,
     Depends => (Is_Auth_Valid => (Has_Valid_Passport, New_Command_Reg)),
     Post    => Is_Auth_Valid = (Has_Valid_Passport = True and then 
                                 (New_Command_Reg and PCI_COMMAND_BUS_MASTER) /= 0);

end Schild_Pcie_Command_Guard;
