with Interfaces;

package Schild_Page_Mapper with
  SPARK_Mode => On
is

   --  A page-table index selects one of 512 entries.
   subtype Page_Table_Index_Range is Natural range 0 .. 511;

   --  The four-level walk indices for a virtual address.
   type Page_Translation_Passport is record
      Pml4_Index : Page_Table_Index_Range;
      Pdpt_Index : Page_Table_Index_Range;
      Pd_Index   : Page_Table_Index_Range;
      Pt_Index   : Page_Table_Index_Range;
   end record;

   --  Split a virtual address into PML4/PDPT/PD/PT indices.
   procedure Decompose_Virtual_Address
     (Virt_Addr : in Interfaces.Unsigned_64;
      Passport  : out Page_Translation_Passport)
   with
     --  Decomposed by 39/30/21/12-bit shifts, so each index is within 0..511.
     Post => Passport.Pml4_Index <= 511
             and Passport.Pdpt_Index <= 511
             and Passport.Pd_Index <= 511
             and Passport.Pt_Index <= 511;

end Schild_Page_Mapper;
