package body Schild_User_Thread with
  SPARK_Mode => Off --  Scaffold: marks the context runnable without a real switch.
is

   procedure Switch_To_User_Context
     (Context : in out User_Thread_Context)
   is
   begin
      --  Mark registers valid and the thread runnable.
      Context.Registers_Ok := True;
      Context.State        := Thread_Runnable;
   end Switch_To_User_Context;

end Schild_User_Thread;
