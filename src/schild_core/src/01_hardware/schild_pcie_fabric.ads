with Interfaces; use Interfaces;
with Schild_Pcie_Bar_Guard;

package Schild_Pcie_Fabric with
  SPARK_Mode => On
is
   pragma Elaborate_Body;

   type Pci_Bus_Range is new Interfaces.Unsigned_8;
   type Pci_Device_Range is new Interfaces.Unsigned_8 range 0 .. 31;
   type Pci_Function_Range is new Interfaces.Unsigned_8 range 0 .. 7;

   type Pcie_Device_Context is record
      Bus_Id    : Pci_Bus_Range := 0;
      Device_Id : Pci_Device_Range := 0;
      Func_Id   : Pci_Function_Range := 0;
      Bar_Addr  : Schild_Pcie_Bar_Guard.Bar_Address_Type := Schild_Pcie_Bar_Guard.Pcie_Min_Allowed_Addr;
      Is_Ready  : Boolean := False;
   end record;

   procedure Initialize_Device
     (Context : in out Pcie_Device_Context;
      Success :    out Boolean)
   with Post => (if Success then Context.Is_Ready);

end Schild_Pcie_Fabric;
