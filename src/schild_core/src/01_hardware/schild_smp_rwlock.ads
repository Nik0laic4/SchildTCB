with Interfaces; use Interfaces;
with Schild_Smp_Spinlock; use Schild_Smp_Spinlock;

package Schild_Smp_Rwlock with
  SPARK_Mode => On
is

   type Rwlock_State is record
      Guard           : Spinlock_State;
      Reader_Count    : Interfaces.Unsigned_32 := 0;
      Is_Write_Locked : Boolean := False;
      Writer_Core     : Schild_Smp_Spinlock.Core_Id_Type := 0;
   end record;

   procedure Acquire_Shared_Read
     (Lock : in out Rwlock_State);

   procedure Release_Shared_Read
     (Lock : in out Rwlock_State)
   with Pre => Lock.Reader_Count > 0;

   procedure Acquire_Exclusive_Write
     (Lock : in out Rwlock_State;
      Core : in     Schild_Smp_Spinlock.Core_Id_Type)
   with Post => Lock.Is_Write_Locked and Lock.Writer_Core = Core;

   procedure Release_Exclusive_Write
     (Lock : in out Rwlock_State;
      Core : in     Schild_Smp_Spinlock.Core_Id_Type)
   with Pre => Lock.Is_Write_Locked and Lock.Writer_Core = Core,
        Post => not Lock.Is_Write_Locked;

end Schild_Smp_Rwlock;
