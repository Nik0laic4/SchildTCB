package body Schild_IPC with SPARK_Mode is

   procedure Write_Byte (Window : in out IPC_Window; Data : Storage_Byte) is
   begin
      Window.Length := Window.Length + 1;
      Window.Buffer (Buffer_Index (Window.Length)) := Data;
   end Write_Byte;

   --  Execute a syscall through the IPC window.
   procedure Execute_Syscall (Window : in out IPC_Window; Slot : Slot_Index) is
   begin
      Window.Buffer := (others => 0);
      Window.Buffer (1) := 200;
      Window.Buffer (2) := 0;
      Window.Buffer (3) := 0;
      Window.Buffer (4) := 0;
      Window.Length := 4;
   end Execute_Syscall;

end Schild_IPC;
