package Schild_IPC with SPARK_Mode is

   Buffer_Size : constant := 4096;
   type Buffer_Index is range 1 .. Buffer_Size;
   type Storage_Byte is mod 256;
   type IPC_Buffer_Type is array (Buffer_Index) of Storage_Byte;

   type Cap_Kind is (Cap_Null, Cap_Read, Cap_Write, Cap_Grant);

   type Capability_Type is record
      Kind : Cap_Kind := Cap_Null;
   end record;

   C_Space_Size : constant := 16;
   type Slot_Index is range 1 .. C_Space_Size;
   type C_Space_Type is array (Slot_Index) of Capability_Type;

   type IPC_Window is record
      Buffer  : IPC_Buffer_Type := (others => 0);
      C_Space : C_Space_Type    := (others => (Kind => Cap_Null));
      Length  : Integer range 0 .. Buffer_Size := 0;
   end record;

   --  Write one byte into the shared IPC window.
   procedure Write_Byte (Window : in out IPC_Window; Data : Storage_Byte)
     with Pre  => Window.Length < Buffer_Size,
          Post => Window.Length = Window.Length'Old + 1 and
                  Window.C_Space = Window.C_Space'Old;

   procedure Execute_Syscall (Window : in out IPC_Window; Slot : Slot_Index)
     with Pre  => Window.Length > 0 and then
                  (Window.C_Space (Slot).Kind = Cap_Write or
                   Window.C_Space (Slot).Kind = Cap_Grant),
          Post => Window.Length = 4;

end Schild_IPC;
