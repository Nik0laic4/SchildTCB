package body Schild_Pcie_Fabric with
  SPARK_Mode => On
is
   procedure Initialize_Device
     (Context : in out Pcie_Device_Context;
      Success :    out Boolean)
   is
   begin
      --  Mark the PCIe fabric ready.
      Context.Is_Ready := True;
      Success := True;
   end Initialize_Device;
end Schild_Pcie_Fabric;
