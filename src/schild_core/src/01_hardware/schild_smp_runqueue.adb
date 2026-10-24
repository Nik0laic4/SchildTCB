with Schild_Smp_Balancer; use Schild_Smp_Balancer;

package body Schild_Smp_Runqueue with
  SPARK_Mode => On
is

   procedure Pop_Next_Task
     (Runqueue : in out Runqueue_Context_Record;
      Success  :    out Boolean)
   is
   begin
      if Runqueue.Task_Count > 0 then
         Runqueue.Task_Count := Runqueue.Task_Count - 1;
         Success := True;
      else
         Success := False;
      end if;
   end Pop_Next_Task;

end Schild_Smp_Runqueue;
