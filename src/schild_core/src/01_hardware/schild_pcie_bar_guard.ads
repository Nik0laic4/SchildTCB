with Interfaces; use Interfaces;

package Schild_Pcie_Bar_Guard with
  SPARK_Mode => On
is
   pragma Elaborate_Body;

   type Bar_Address_Type is new Interfaces.Unsigned_64;
   
   --  BARs must map above 4 GB.
   Pcie_Min_Allowed_Addr : constant Bar_Address_Type := 16#0000_0001_0000_0000#;

   procedure Validate_Bar_Range
     (Addr  : in     Bar_Address_Type;
      Valid :    out Boolean)
   with Post => (if Valid then Addr >= Pcie_Min_Allowed_Addr);

end Schild_Pcie_Bar_Guard;
