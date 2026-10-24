with Interfaces; use Interfaces;

package Schild_Mmu_Overseer with
  SPARK_Mode => On
is
   pragma Elaborate_Body;

   type Physical_Address is new Interfaces.Unsigned_64;
   
   --  Kernel physical memory ends at 4 GB.
   Kernel_Physical_Limit : constant Physical_Address := 16#0000_0001_0000_0000#; -- 4GB

   procedure Validate_Page_Alignment
     (Addr  : in     Physical_Address;
      Valid :    out Boolean)
   with Post => (if Valid then (Addr and 16#0FFF#) = 0);

end Schild_Mmu_Overseer;
