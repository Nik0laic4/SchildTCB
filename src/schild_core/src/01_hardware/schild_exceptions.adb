package body Schild_Exceptions with SPARK_Mode is

   procedure Raise_Fault
     (Sched : in out Scheduler_Type;
      Id    :        Valid_Task_Id;
      Fault :        Fault_Record) is
   begin
      pragma Unreferenced (Fault); --  Fault not used in the scaffold.
      Sched.Tasks (Id).State := Task_Blocked;
   end Raise_Fault;

end Schild_Exceptions;
