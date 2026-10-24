with System.Machine_Code; use System.Machine_Code;

package body Schild_Smp_Rwlock with
  SPARK_Mode => Off --  Reader/writer lock guarded by the atomic spinlock.
is

   procedure Acquire_Shared_Read (Lock : in out Rwlock_State) is
   begin
      loop
         Acquire_Lock (Lock.Guard, 0);
         if not Lock.Is_Write_Locked then
            Lock.Reader_Count := Lock.Reader_Count + 1;
            Release_Lock (Lock.Guard, 0);
            exit;
         end if;
         Release_Lock (Lock.Guard, 0);
         Asm (Template => "pause", Volatile => True);
      end loop;
   end Acquire_Shared_Read;

   procedure Release_Shared_Read (Lock : in out Rwlock_State) is
   begin
      Acquire_Lock (Lock.Guard, 0);
      Lock.Reader_Count := Lock.Reader_Count - 1;
      Release_Lock (Lock.Guard, 0);
   end Release_Shared_Read;

   procedure Acquire_Exclusive_Write
     (Lock : in out Rwlock_State;
      Core : in     Schild_Smp_Spinlock.Core_Id_Type)
   is
   begin
      loop
         Acquire_Lock (Lock.Guard, Core);
         if not Lock.Is_Write_Locked and Lock.Reader_Count = 0 then
            Lock.Is_Write_Locked := True;
            Lock.Writer_Core     := Core;
            Release_Lock (Lock.Guard, Core);
            exit;
         end if;
         Release_Lock (Lock.Guard, Core);
         Asm (Template => "pause", Volatile => True);
      end loop;
   end Acquire_Exclusive_Write;

   procedure Release_Exclusive_Write
     (Lock : in out Rwlock_State;
      Core : in     Schild_Smp_Spinlock.Core_Id_Type)
   is
      pragma Unreferenced (Core);
   begin
      Acquire_Lock (Lock.Guard, 0);
      Lock.Is_Write_Locked := False;
      Release_Lock (Lock.Guard, 0);
   end Release_Exclusive_Write;

end Schild_Smp_Rwlock;
