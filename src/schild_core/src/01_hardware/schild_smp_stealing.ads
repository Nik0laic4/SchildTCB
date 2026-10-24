with Interfaces; use Interfaces;
with Schild_Smp_Spinlock; use Schild_Smp_Spinlock;
with Schild_Smp_Balancer; use Schild_Smp_Balancer;

package Schild_Smp_Stealing with
  SPARK_Mode => On
is

   pragma Elaborate_Body;

   type Steal_Passport_Record is record
      Victim_Core  : Schild_Smp_Balancer.Core_Index_Type := 0;
      Thief_Core   : Schild_Smp_Balancer.Core_Index_Type := 0;
      Tasks_Stolen : Schild_Smp_Balancer.Task_Count_Type := 0;
   end record;

   procedure Execute_Work_Stealing
     (Passport : in out Steal_Passport_Record;
      Success  :    out Boolean)
   with Pre => Passport.Victim_Core /= Passport.Thief_Core,
        Post => (if Success then Passport.Tasks_Stolen > 0);

end Schild_Smp_Stealing;
