package body Schild_Huge_Page_Mapper with
  SPARK_Mode => Off --  Huge-page mapping scaffold.
is

   procedure Map_2MB_Huge_Page
     (Phys_Addr : in     Physical_Huge_Address;
      Is_Mapped :    out Boolean)
   is
      pragma Unreferenced (Phys_Addr);
   begin
      --  Not implemented: a real 2 MiB mapping requires writing the PDE with
      --  the PS bit in the current page table (CR3) — out of scope. Report
      --  honestly instead of claiming a successful mapping.
      Is_Mapped := False;
   end Map_2MB_Huge_Page;

end Schild_Huge_Page_Mapper;
