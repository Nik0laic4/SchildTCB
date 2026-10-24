package body Schild_Mmu_Overseer with
  SPARK_Mode => On
is
   procedure Validate_Page_Alignment
     (Addr  : in     Physical_Address;
      Valid :    out Boolean)
   is
   begin
      Valid := (Addr and 16#0FFF#) = 0;
   end Validate_Page_Alignment;
end Schild_Mmu_Overseer;
