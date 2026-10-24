package body Schild_Pcie_Bar_Guard with
  SPARK_Mode => On
is
   procedure Validate_Bar_Range
     (Addr  : in     Bar_Address_Type;
      Valid :    out Boolean)
   is
   begin
      --  Valid when at or above the minimum address.
      Valid := Addr >= Pcie_Min_Allowed_Addr;
   end Validate_Bar_Range;
end Schild_Pcie_Bar_Guard;
