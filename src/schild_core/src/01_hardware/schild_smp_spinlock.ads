with Interfaces; use Interfaces;

package Schild_Smp_Spinlock with
  SPARK_Mode => On
is

   --  A core identifier used by the spinlock owner.
   type Core_Id_Type is new Interfaces.Unsigned_32;
   type Spinlock_State is record
      Word       : Interfaces.Unsigned_32 := 0;  -- 0 = unlocked, /= 0 = locked (single atomic word)
      Owner_Core : Core_Id_Type := 0;
   end record;

   procedure Acquire_Lock
     (Lock  : in out Spinlock_State;
      Core  : in     Core_Id_Type)
   with Post => Lock.Word /= 0 and Lock.Owner_Core = Core;

   procedure Release_Lock
     (Lock  : in out Spinlock_State;
      Core  : in     Core_Id_Type)
   with Pre => Lock.Word /= 0 and Lock.Owner_Core = Core,
        Post => Lock.Word = 0;

end Schild_Smp_Spinlock;
