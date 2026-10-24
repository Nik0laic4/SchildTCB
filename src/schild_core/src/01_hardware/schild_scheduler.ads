with Interfaces; use Interfaces;
with Schild_MTF; use Schild_MTF;

package Schild_Scheduler with SPARK_Mode is

   Max_Tasks : constant := 8;
   type Task_Id is range 0 .. Max_Tasks;
   subtype Valid_Task_Id is Task_Id range 1 .. Max_Tasks;

   type Task_State is (Task_Empty, Task_Ready, Task_Blocked);
   type Priority_Type is range 0 .. 255;

   --  Saved general-purpose registers of a task.
   type CPU_Context is record
      RAX : Unsigned_64 := 0;
      RBX : Unsigned_64 := 0;
      RCX : Unsigned_64 := 0;
      RDX : Unsigned_64 := 0;
      RSP : Unsigned_64 := 0; --  Stack pointer.
      RIP : Unsigned_64 := 0; --  Instruction pointer.
   end record with Pack;

   -- 2. Update TCB: now each task has its own saved context CPU!
   type TCB is record
      State     : Task_State  := Task_Empty;
      Priority  : Priority_Type := 0;
      Partition : Partition_Id := 1;  --  owning ARINC 653 partition
      Context   : CPU_Context;        --  Saved registers for this task.
   end record;

   type Task_Table_Type is array (Valid_Task_Id) of TCB;

   type Scheduler_Type is record
      Tasks        : Task_Table_Type := (others => (State => Task_Empty, Priority => 0, Partition => 1, Context => (others => 0)));
      Current_Task : Task_Id         := 0;
   end record;

   function Find_Next_Task (Sched : Scheduler_Type) return Task_Id
     with Post => (if Find_Next_Task'Result > 0 then 
                     Sched.Tasks (Valid_Task_Id (Find_Next_Task'Result)).State = Task_Ready);

   -- Highest-priority ready task within a given partition (two-level schedule).
   function Find_Next_Task_In_Partition (Sched : Scheduler_Type; P : Partition_Id)
     return Task_Id
     with Post => (if Find_Next_Task_In_Partition'Result > 0 then
                     Sched.Tasks (Valid_Task_Id (Find_Next_Task_In_Partition'Result)).State = Task_Ready
                     and then Sched.Tasks (Valid_Task_Id (Find_Next_Task_In_Partition'Result)).Partition = P);

   --  Save the current task's context (RAX captured from the incoming register).
   procedure Save_Task_Context (Sched : in out Scheduler_Type; Id : Valid_Task_Id; Incoming_RAX : Unsigned_64)
     with Post => Sched.Tasks (Id).Context.RAX = Incoming_RAX;

end Schild_Scheduler;
