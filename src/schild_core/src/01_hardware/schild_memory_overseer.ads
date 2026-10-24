with Interfaces; use Interfaces;
with Schild_Mmu_Overseer; use Schild_Mmu_Overseer;

package Schild_Memory_Overseer with
  SPARK_Mode => On
is
   pragma Elaborate_Body;

   type Memory_Region_Status is (System_Reserved, Available, Allocated_User, Faulty);

   --  Memory below 1 GB is reserved for the kernel.
   Kernel_Reserved_Boundary : constant Schild_Mmu_Overseer.Physical_Address := 16#4000_0000#;

   procedure Request_Memory_Region
     (Base_Addr : in     Schild_Mmu_Overseer.Physical_Address;
      Size      : in     Interfaces.Unsigned_64;
      Status    :    out Memory_Region_Status)
   with Pre  => Base_Addr /= 0 and Size > 0,
        Post => (if Status = Available then Base_Addr >= Kernel_Reserved_Boundary);

end Schild_Memory_Overseer;
