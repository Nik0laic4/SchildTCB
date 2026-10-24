--  Schild TCB - root task body (stub).
--  Validates boot capabilities, waits for the first IPC, then allocates and
--  delegates a frame.

with Schild_Log;
with Schild_Sel4_Ipc;

package body Schild_Root_Task with
  SPARK_Mode => On
is
   use Schild_Sel4_Ipc;

   function Is_Valid_Cap (Cap : Cap_Id) return Boolean is
   begin
      return Cap /= Null_Cap;
   end Is_Valid_Cap;

   procedure Allocate_Frame (Context : in out Root_Task_Context; Size : Interfaces.Unsigned_64) is
      Frame_Cap : Cap_Id := Null_Cap;
   begin
      Schild_Log.Put_Line ("RootTask: allocating frame...");
      Retype_Untyped
        (Untyped_Cap   => Context.Untyped_Memory,
         Target_Type   => 16#0001#,       -- Code Frame
         Size_Bits     => Interfaces.Unsigned_32 (Size),
         Out_Frame_Cap => Frame_Cap);
   end Allocate_Frame;

   procedure Delegate_Cap (Context : in out Root_Task_Context; Cap : Cap_Id) is
      Dest_Cap : Cap_Id := Null_Cap;  --  Minted copy returned by the CNode.
   begin
      Schild_Log.Put_Line ("RootTask: delegating capability...");
      CNode_Mint
        (CNode  => Context.CNode_Cap,
         Src    => Cap,
         Dest   => Dest_Cap,
         Rights => Read_Right or Write_Right,
         Badge  => 0);
   end Delegate_Cap;

   procedure Run_Root_Task (Context : in out Root_Task_Context) is
   begin
      Schild_Log.Put_Line ("[SE4L] Root Task (PID 1) starting...");
      Schild_Log.Put_Line ("[SE4L] BootInfo: Caps received from seL4");

      --  Report which boot capabilities are present.
      if Is_Valid_Cap (Context.Task_Cap) and
         Is_Valid_Cap (Context.CNode_Cap) and
         Is_Valid_Cap (Context.VSpace) and
         Is_Valid_Cap (Context.Ipc_Buffer) and
         Is_Valid_Cap (Context.Untyped_Memory)
      then
         Schild_Log.Put_Line ("[SE4L] All Root Task Caps validated");
      else
         Schild_Log.Put_Line ("[SE4L] WARNING: some Caps are NULL (stub mode)");
      end if;

      --  Block for the first incoming IPC.
      declare
         Incoming_Label : Ipc_Label := 0;
      begin
         Wait (Src => Context.Task_Cap, Out_Label => Incoming_Label);
         Schild_Log.Put_Line ("[SE4L] IPC label received: stub");
      end;

      --  Allocate a 4 KiB frame and delegate a capability to it.
      Allocate_Frame (Context, Size => 12); -- 4 KiB page
      Delegate_Cap   (Context, Cap => Context.Untyped_Memory);

      Schild_Log.Put_Line ("[SE4L] Root Task initialization complete");
   end Run_Root_Task;

end Schild_Root_Task;