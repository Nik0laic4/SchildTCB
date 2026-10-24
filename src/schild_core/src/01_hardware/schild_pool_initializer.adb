with Schild_Mmu_Overseer; use Schild_Mmu_Overseer;

package body Schild_Pool_Initializer with
  SPARK_Mode => On --  Frame pool initializer.
is

   procedure Initialize_Hardware_Pool
     (Pool    : in out Memory_Pool_Record;
      Success :    out Boolean)
   is
   begin
      if Pool.Base_Addr /= 0 then
         Pool.Status := Pool_Ready;
         Success     := True;
      else
         Pool.Status := Pool_Fault;
         Success     := False;
      end if;
   end Initialize_Hardware_Pool;

end Schild_Pool_Initializer;
