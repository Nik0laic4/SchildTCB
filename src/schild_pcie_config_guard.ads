with Interfaces;
with Schild_Mmio_Mapper;

package Schild_Pcie_Config_Guard with
  SPARK_Mode => On
is

   --  PCI bus/device/function/register ranges.
   subtype Pcie_Bus_Range is Natural range 0 .. 255;
   subtype Pcie_Device_Range is Natural range 0 .. 31;
   subtype Pcie_Function_Range is Natural range 0 .. 7;
   subtype Pcie_Register_Range is Natural range 0 .. 4095;

   --  ECAM window size (256 MB).
   Pcie_Ecam_Size : constant Interfaces.Unsigned_64 := 16#1000_0000#;

   --  Result of computing an ECAM address.
   type Pcie_Access_Passport is record
      Physical_Config_Addr : Interfaces.Unsigned_64;
      Is_Within_Ecam_Range : Boolean;
      Is_Aligned           : Boolean;
   end record;

   --  Compute a bus/device/function/register ECAM address.
   procedure Compute_Ecam_Address
     (Bus      : in Pcie_Bus_Range;
      Device   : in Pcie_Device_Range;
      Func     : in Pcie_Function_Range;
      Register : in Pcie_Register_Range;
      Passport : out Pcie_Access_Passport;
      Success  : out Boolean)
   with
     --  On success the address is inside the ECAM window and aligned.
     Post => (if Success then 
                Passport.Is_Within_Ecam_Range
                and Passport.Is_Aligned
                and Passport.Physical_Config_Addr >= Schild_Mmio_Mapper.Pcie_Ecft_Physical
                and Passport.Physical_Config_Addr < Schild_Mmio_Mapper.Pcie_Ecft_Physical + Pcie_Ecam_Size
                and (Passport.Physical_Config_Addr and 16#03#) = 0);

end Schild_Pcie_Config_Guard;
