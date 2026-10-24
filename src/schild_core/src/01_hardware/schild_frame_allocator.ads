with Interfaces; use Interfaces;
with Schild_Mmu_Overseer; use Schild_Mmu_Overseer;
with Schild_Frame_Deallocator;

package Schild_Frame_Allocator with
  SPARK_Mode => On
is
   pragma Elaborate_Body;

   procedure Allocate_Physical_Frame
     (Passport : in out Schild_Frame_Deallocator.Frame_Deallocate_Passport;
      Success  :    out Boolean)
   with Pre  => not Passport.Is_Freed,
        Post => (if Success then (Passport.Physical_Address and 16#0FFF#) = 0 
                 and Passport.Physical_Address < Schild_Mmu_Overseer.Kernel_Physical_Limit);

end Schild_Frame_Allocator;
