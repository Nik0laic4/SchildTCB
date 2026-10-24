pragma Spark_Mode (On);

package Schild_Pcie_Config_Guard is

   type Pcie_Bus      is range 0 .. 255;
   type Pcie_Device   is range 0 .. 31;
   type Pcie_Function is range 0 .. 7;
   type Pcie_Register is range 0 .. 4095;
   type Phys_Addr_64  is mod 2**64;

   --  ECAM window: base 3.5 GB, size 256 MB.
   ECAM_BASE_ADDR : constant Phys_Addr_64 := 16#0000_0000_E000_0000#; -- 3.5 GB
   ECAM_MAX_SIZE  : constant Phys_Addr_64 := 16#0000_0000_1000_0000#; -- 256 MB

   --  Compute a bus/device/function/register ECAM address, 4-byte aligned.
   procedure Calculate_Ecam_Address
     (Bus          : in     Pcie_Bus;
      Device       : in     Pcie_Device;
      Func         : in     Pcie_Function;
      Reg          : in     Pcie_Register;
      Ecam_Address :    out Phys_Addr_64;
      Is_Addr_Safe :    out Boolean)
   with
     Global  => null,
     Depends => (Ecam_Address => (Bus, Device, Func, Reg), Is_Addr_Safe => (Bus, Device, Func, Reg)),
     Post    => (if Is_Addr_Safe then
                   Ecam_Address >= ECAM_BASE_ADDR and
                   Ecam_Address < ECAM_BASE_ADDR + ECAM_MAX_SIZE and
                   (Ecam_Address and 3) = 0 --  4-byte aligned.
                 else
                   Ecam_Address = 0);

end Schild_Pcie_Config_Guard;
