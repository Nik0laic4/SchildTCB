pragma Spark_Mode (On);

package body Schild_Pcie_Config_Guard is

   procedure Calculate_Ecam_Address
     (Bus          : in     Pcie_Bus;
      Device       : in     Pcie_Device;
      Func         : in     Pcie_Function;
      Reg          : in     Pcie_Register;
      Ecam_Address :    out Phys_Addr_64;
      Is_Addr_Safe :    out Boolean)
   is
      Offset       : Phys_Addr_64;
      Is_Safe_Addr : Boolean;
   begin
      --  Only 4-byte-aligned registers are addressable.
      if Reg mod 4 = 0 then
         Offset := (Phys_Addr_64(Bus) * 2**20) +
                   (Phys_Addr_64(Device) * 2**15) +
                   (Phys_Addr_64(Func) * 2**12) +
                   Phys_Addr_64(Reg);
         
         Ecam_Address := ECAM_BASE_ADDR + Offset;
         Is_Safe_Addr := (Offset < ECAM_MAX_SIZE);
         
         if Is_Safe_Addr then
            Is_Addr_Safe := True;
         else
            Ecam_Address := 0;
            Is_Addr_Safe := False;
         end if;
      else
         Ecam_Address := 0;
         Is_Addr_Safe := False;
      end if;
   end Calculate_Ecam_Address;

end Schild_Pcie_Config_Guard;
