with Interfaces; use Interfaces;

package Schild_Huge_Page_Mapper with
  SPARK_Mode => On
is

   --  A 2 MiB-aligned physical address.
   type Physical_Huge_Address is new Interfaces.Unsigned_64;

   procedure Map_2MB_Huge_Page
     (Phys_Addr : in     Physical_Huge_Address;
      Is_Mapped :    out Boolean)
   with Pre => (Phys_Addr and 16#1F_FFFF#) = 0; --  2 MiB alignment.

end Schild_Huge_Page_Mapper;
