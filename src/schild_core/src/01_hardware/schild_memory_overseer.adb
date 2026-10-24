package body Schild_Memory_Overseer with
  SPARK_Mode => On
is

   procedure Request_Memory_Region
     (Base_Addr : in     Schild_Mmu_Overseer.Physical_Address;
      Size      : in     Interfaces.Unsigned_64;
      Status    :    out Memory_Region_Status)
   is
   begin
      --  Reject regions below the kernel-reserved boundary.
      if Base_Addr < Kernel_Reserved_Boundary then
         Status := System_Reserved;
      else
         --  Otherwise the region is available.
         Status := Available;
      end if;
   end Request_Memory_Region;

end Schild_Memory_Overseer;
