package body Schild_Scheduler with SPARK_Mode is

   function Find_Next_Task (Sched : Scheduler_Type) return Task_Id is
      Max_Pri : Priority_Type := 0;
      Best_Id : Task_Id := 0;
   begin
      --  Scan for the highest-priority ready task.
      for Id in Valid_Task_Id loop
         if Sched.Tasks (Id).State = Task_Ready then
            --  Track the best (highest-priority) candidate.
            if Sched.Tasks (Id).Priority >= Max_Pri then
               Max_Pri := Sched.Tasks (Id).Priority;
               Best_Id := Id;
            end if;
         end if;

         pragma Loop_Invariant
           ((if Best_Id = 0 then Max_Pri = 0
             else (Best_Id in Valid_Task_Id
                   and Sched.Tasks (Best_Id).State = Task_Ready
                   and Sched.Tasks (Best_Id).Priority = Max_Pri))
            and (for all J in Valid_Task_Id'First .. Id =>
                   (if Sched.Tasks (J).State = Task_Ready then
                      Sched.Tasks (J).Priority <= Max_Pri)));
      end loop;

      return Best_Id;
   end Find_Next_Task;

   function Find_Next_Task_In_Partition (Sched : Scheduler_Type; P : Partition_Id)
     return Task_Id is
      Max_Pri : Priority_Type := 0;
      Best_Id : Task_Id := 0;
   begin
      --  Scan for the highest-priority ready task in partition P.
      for Id in Valid_Task_Id loop
         if Sched.Tasks (Id).State = Task_Ready
           and then Sched.Tasks (Id).Partition = P then
            if Sched.Tasks (Id).Priority >= Max_Pri then
               Max_Pri := Sched.Tasks (Id).Priority;
               Best_Id := Id;
            end if;
         end if;

         pragma Loop_Invariant
           ((if Best_Id = 0 then Max_Pri = 0
             else (Best_Id in Valid_Task_Id
                   and Sched.Tasks (Best_Id).State = Task_Ready
                   and Sched.Tasks (Best_Id).Partition = P
                   and Sched.Tasks (Best_Id).Priority = Max_Pri))
            and (for all J in Valid_Task_Id'First .. Id =>
                   (if Sched.Tasks (J).State = Task_Ready
                      and then Sched.Tasks (J).Partition = P then
                      Sched.Tasks (J).Priority <= Max_Pri)));
      end loop;
      return Best_Id;
   end Find_Next_Task_In_Partition;
   procedure Save_Task_Context (Sched : in out Scheduler_Type; Id : Valid_Task_Id; Incoming_RAX : Unsigned_64) is
   begin
      --  Store the captured RAX into the task's saved context.
      Sched.Tasks (Id).Context.RAX := Incoming_RAX;
   end Save_Task_Context;

end Schild_Scheduler;
