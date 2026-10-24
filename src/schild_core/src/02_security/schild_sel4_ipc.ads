-- Schild TCB seL4 IPC Primitives
--  Capability IDs, IPC labels, capability rights and the syscall entry points
--  that back inter-process communication on the seL4 microkernel.

with Interfaces;
with System;

package Schild_Sel4_Ipc with
  SPARK_Mode => On
is
   pragma Elaborate_Body;

   --  Opaque capability identifier (0 is the null capability).
   type Cap_Id is mod 2**64;
   Null_Cap : constant Cap_Id := 0;

   --  A single IPC message register (MR word).
   subtype Message_Register is Interfaces.Unsigned_64;
   Max_MR : constant := 5;

   --  The user-chosen label carried by every IPC.
   subtype Ipc_Label is Interfaces.Unsigned_64;

   --  Bitmask of capability rights (read/write/grant).
   type Cap_Rights is mod 2**8;
   Read_Right  : constant Cap_Rights := 1;
   Write_Right : constant Cap_Rights := 2;
   Grant_Right : constant Cap_Rights := 4;

   ------------------------------------------------------------
   --  Basic IPC operations.
   ------------------------------------------------------------

   --  Send a message to the endpoint Dest.
   procedure Send (Dest : Cap_Id; Label : Ipc_Label);

   --  Receive a message from the endpoint Src.
   procedure Recv (Src : Cap_Id; Out_Label : out Ipc_Label);

   --  Synchronous call: send then block for the reply label.
   procedure Call (Dest : Cap_Id; Label : Ipc_Label; Reply_Label : out Ipc_Label);

   --  Reply to the last call received on Dest.
   procedure Reply (Dest : Cap_Id);

   --  Block until a message arrives on Src.
   procedure Wait (Src : Cap_Id; Out_Label : out Ipc_Label);

   --  Yield the current timeslice.
   procedure Yield;

   --  Signal that the seL4 kernel is present / query its availability.
   procedure Mark_Sel4_Present;
   function  Is_Sel4_Active return Boolean;

   ------------------------------------------------------------
   --  Capability-management operations.
   ------------------------------------------------------------

   --  Retype an untyped region into a new kernel object.
   procedure Retype_Untyped
     (Untyped_Cap    : Cap_Id;
      Target_Type    : Interfaces.Unsigned_64;
      Size_Bits      : Interfaces.Unsigned_32;
      Out_Frame_Cap  : out Cap_Id);

   --  Mint (copy with rights/badge) a capability through a CNode.
   procedure CNode_Mint
     (CNode  : Cap_Id;
      Src    : Cap_Id;
      Dest   : out Cap_Id;
      Rights : Cap_Rights;
      Badge  : Interfaces.Unsigned_64);

   --  Delete a capability from a CNode slot.
   procedure CNode_Delete
     (CNode : Cap_Id;
      Slot  : Interfaces.Unsigned_64);

private
   --  Raw syscall entry point (imported from the C stub).
   procedure Sel4_Syscall
     (Syscall_Id : Interfaces.Unsigned_32;
      Arg1, Arg2 : System.Address;
      Out_Label  : out Ipc_Label);
   pragma Import (C, Sel4_Syscall, "schild_sel4_syscall");
end Schild_Sel4_Ipc;