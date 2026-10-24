package body Schild_Page_Mapper with
  SPARK_Mode => On
is

   -------------------------------
   -- Decompose_Virtual_Address --
   -------------------------------
   procedure Decompose_Virtual_Address
     (Virt_Addr : in Interfaces.Unsigned_64;
      Passport  : out Page_Translation_Passport)
   is
      use type Interfaces.Unsigned_64;
   begin
      --  Extract each level's 9-bit index from the virtual address.

      Passport.Pml4_Index := Page_Table_Index_Range (Interfaces.Shift_Right (Virt_Addr, 39) and 16#1FF#);
      Passport.Pdpt_Index := Page_Table_Index_Range (Interfaces.Shift_Right (Virt_Addr, 30) and 16#1FF#);
      Passport.Pd_Index   := Page_Table_Index_Range (Interfaces.Shift_Right (Virt_Addr, 21) and 16#1FF#);
      Passport.Pt_Index   := Page_Table_Index_Range (Interfaces.Shift_Right (Virt_Addr, 12) and 16#1FF#);
   end Decompose_Virtual_Address;

end Schild_Page_Mapper;
