with Interfaces; use Interfaces;
with Schild_Smp_Spinlock;

package Schild_Smp_Panic with
  SPARK_Mode => On
is

   type Crash_Reason_Code is new Interfaces.Unsigned_32;

   procedure Trigger_Smp_Cascade_Panic
     (Faulty_Core : in     Schild_Smp_Spinlock.Core_Id_Type;
      Reason      : in     Crash_Reason_Code)
   with No_Return; --  Panic never returns.

end Schild_Smp_Panic;
