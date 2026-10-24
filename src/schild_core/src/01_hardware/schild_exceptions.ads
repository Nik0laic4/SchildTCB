with Interfaces;    use Interfaces;
with Schild_Scheduler; use Schild_Scheduler;

package Schild_Exceptions with SPARK_Mode is

   type Exception_Kind is
     (Ex_Divide_By_Zero,
      Ex_General_Protection,
      Ex_Page_Fault);

   type Fault_Record is record
      Kind    : Exception_Kind := Ex_Divide_By_Zero;
      Address : Unsigned_64    := 0;
   end record;

   procedure Raise_Fault
     (Sched : in out Scheduler_Type;
      Id    :        Valid_Task_Id;
      Fault :        Fault_Record)
   with
     Post => Sched.Tasks (Id).State = Task_Blocked;

end Schild_Exceptions;
