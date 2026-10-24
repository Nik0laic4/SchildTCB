with Interfaces; use Interfaces;
with Schild_Smp_Balancer; use Schild_Smp_Balancer;
with Schild_Smp_Spinlock;

package Schild_Smp_Runqueue with
  SPARK_Mode => On
is
   pragma Elaborate_Body;

   type Runqueue_Id_Type is new Interfaces.Unsigned_32 range 1 .. 65535;
   
   type Runqueue_Context_Record is record
      Id           : Runqueue_Id_Type := 1;
      Task_Count   : Schild_Smp_Balancer.Task_Count_Type := 0;
      Lock         : Schild_Smp_Spinlock.Spinlock_State;
      Is_Available : Boolean := False;
   end record;

   procedure Pop_Next_Task
     (Runqueue : in out Runqueue_Context_Record;
      Success  :    out Boolean)
   with Pre  => Runqueue.Task_Count > 0,
        Post => (if Success then Runqueue.Task_Count = Runqueue.Task_Count'Old - 1);

end Schild_Smp_Runqueue;
