with Interfaces; use Interfaces;
with Schild_Mmu_Overseer; use Schild_Mmu_Overseer;

package Schild_Pool_Initializer with
  SPARK_Mode => On
is
   pragma Elaborate_Body;

   type Pool_Status_Type is (Pool_Empty, Pool_Initializing, Pool_Ready, Pool_Fault);
   subtype Pool_Size_Type is Interfaces.Unsigned_32 range 1 .. 1048576;

   type Memory_Pool_Record is record
      Base_Addr    : Schild_Mmu_Overseer.Physical_Address := 0;
      Total_Frames : Pool_Size_Type := 1;
      Status       : Pool_Status_Type := Pool_Empty;
   end record;

   procedure Initialize_Hardware_Pool
     (Pool    : in out Memory_Pool_Record;
      Success :    out Boolean)
   with Pre  => Pool.Base_Addr /= 0,
        Post => (if Success then Pool.Status = Pool_Ready);

end Schild_Pool_Initializer;
