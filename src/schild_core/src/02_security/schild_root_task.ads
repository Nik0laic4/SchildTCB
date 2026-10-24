--  Schild TCB - root task (PID 1) context.
--  Holds the boot capabilities delegated by the seL4 kernel and the entry point
--  that validates them and starts the task.

with System;
with Interfaces;
with Schild_Sel4_Ipc;

package Schild_Root_Task with
  SPARK_Mode => On
is
   pragma Elaborate_Body;

   use Schild_Sel4_Ipc;
   use Interfaces;

   --  Boot capabilities handed to the root task by seL4.
   type Root_Task_Context is record
      Task_Cap       : Cap_Id := Null_Cap;
      CNode_Cap      : Cap_Id := Null_Cap;
      VSpace         : Cap_Id := Null_Cap;
      Ipc_Buffer     : Cap_Id := Null_Cap;
      Untyped_Memory : Cap_Id := Null_Cap;
      Boot_Info_Addr : System.Address := System.Null_Address;
   end record;

   --  Validate capabilities and start the root task.
   procedure Run_Root_Task (Context : in out Root_Task_Context);

   --  True when the capability is not the null capability.
   function  Is_Valid_Cap (Cap : Cap_Id) return Boolean;
   procedure Allocate_Frame (Context : in out Root_Task_Context; Size : Unsigned_64)
   with Pre => Size <= Unsigned_64 (Unsigned_32'Last);
   procedure Delegate_Cap   (Context : in out Root_Task_Context; Cap : Cap_Id);
end Schild_Root_Task;