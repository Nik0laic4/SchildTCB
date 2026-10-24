with Interfaces; use Interfaces;
with Schild_Smp_Spinlock;

package Schild_Smp_Time with
  SPARK_Mode => On
is

   type Tsc_Tick_Count is new Interfaces.Unsigned_64;
   type Time_Sync_Status is (Sync_Ideal, Sync_Drift_Detected, Sync_Failed);

   type Core_Time_Record is record
      Core_Id    : Schild_Smp_Spinlock.Core_Id_Type := 0;
      Last_Tick  : Tsc_Tick_Count := 0;
      Status     : Time_Sync_Status := Sync_Failed;
   end record;

   procedure Synchronize_Core_Tsc
     (Time_Card : in out Core_Time_Record;
      Max_Drift : in     Tsc_Tick_Count;
      Success   :    out Boolean)
   with Pre => Max_Drift > 0,
        Post => (if Success then Time_Card.Status = Sync_Ideal);

end Schild_Smp_Time;
