with Interfaces; use Interfaces;
with Schild_Smp_Spinlock;

package Schild_Smp_Overseer with
  SPARK_Mode => On
is

   type Overseer_State_Type is (Overseer_Active, Overseer_Core_Frozen, Overseer_Reset_Issued);

   type Watchdog_Passport is record
      Monitored_Core : Schild_Smp_Spinlock.Core_Id_Type := 0;
      Heartbeat_Count: Interfaces.Unsigned_64 := 0;
      State          : Overseer_State_Type := Overseer_Active;
   end record;

   procedure Audit_Core_Liveness
     (Passport : in out Watchdog_Passport;
      Is_Alive :    out Boolean)
   with Post => (if not Is_Alive then Passport.State = Overseer_Core_Frozen);

end Schild_Smp_Overseer;
