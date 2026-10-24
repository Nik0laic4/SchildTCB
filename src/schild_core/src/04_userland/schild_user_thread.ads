with Interfaces; use Interfaces;

package Schild_User_Thread with
  SPARK_Mode => On
is

   type Thread_Id_Type is new Interfaces.Unsigned_32 range 1 .. 65535;
   type Thread_State_Type is (Thread_Runnable, Thread_Suspended, Thread_Terminated);

   type User_Thread_Context is record
      Thread_Id    : Thread_Id_Type;
      State        : Thread_State_Type := Thread_Suspended;
      Registers_Ok : Boolean := False;
   end record;

   procedure Switch_To_User_Context
     (Context : in out User_Thread_Context)
   with Post => Context.Registers_Ok and Context.State = Thread_Runnable;

end Schild_User_Thread;
