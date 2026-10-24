--  Schild TCB - seL4 IPC body (stub).
--  Wraps the seL4 syscall ABI behind the Send/Recv/Call/Reply/Yield interface
--  and the capability-management operations (retype/mint/delete).

with System.Machine_Code;
with Interfaces;
with System;
with Schild_Uart_Driver;

package body Schild_Sel4_Ipc with
  SPARK_Mode => Off
is
   use Interfaces;

   SEL4_SEND         : constant := -1;
   SEL4_NBSEND       : constant := -2;
   SEL4_RECV         : constant := -3;
   SEL4_NBRECV       : constant := -4;
   SEL4_CALL         : constant := -5;
   SEL4_REPLY        : constant := -6;
   SEL4_YIELD        : constant := -7;
   SEL4_NBWAIT       : constant := -8;
   SEL4_RETYPE       : constant := -9;
   SEL4_CNODE_REVOKE : constant := -10;
   SEL4_CNODE_DELETE : constant := -11;
   SEL4_CNODE_COPY   : constant := -12;
   SEL4_CNODE_MINT   : constant := -13;

   function Msg_Info (Label : Ipc_Label; Caps : Unsigned_32; Len : Unsigned_32) return Unsigned_64 is
   begin
      return (Unsigned_64 (Label) * 2**12) or
             (Unsigned_64 (Caps)  * 2**7)  or
              Unsigned_64 (Len);
   end Msg_Info;

   Sel4_Present : Boolean := False;

   function Do_Syscall
     (Syscall_No : Integer;
      Info       : Unsigned_64;
      MR0, MR1, MR2, MR3, MR4 : Unsigned_64 := 0)
      return Unsigned_64 is
      Result : Unsigned_64 := 16#FFFF_FFFF_FFFF_FFFF#;
   begin
      if not Sel4_Present then
         return Result;
      end if;
      System.Machine_Code.Asm
        (Template =>
           "syscall"            & ASCII.LF & ASCII.HT &
           "movq %%rax, %0",
         Outputs  => Unsigned_64'Asm_Output ("=r", Result),
         Inputs   =>
           (Integer'Asm_Input  ("a", Syscall_No),
            Unsigned_64'Asm_Input ("D", Info),
            Unsigned_64'Asm_Input ("S", MR0),
            Unsigned_64'Asm_Input ("d", MR1),
            Unsigned_64'Asm_Input ("c", MR2),
            Unsigned_64'Asm_Input ("r", MR3),
            Unsigned_64'Asm_Input ("r", MR4)),
         Clobber  => "memory",
         Volatile => True);
      return Result;
   end Do_Syscall;

   --  Detect the microkernel; stub always reports it absent.
   procedure Probe_Sel4 is
   begin
      Sel4_Present := False;
      Schild_Uart_Driver.Put_Line ("[SE4L] Microkernel not present (stub mode)");
   end Probe_Sel4;

   --  Mark the microkernel as active (called once the kernel is up).
   procedure Mark_Sel4_Present is
   begin
      Sel4_Present := True;
      Schild_Uart_Driver.Put_Line ("[SE4L] Microkernel detected and activated");
   end Mark_Sel4_Present;

   function Is_Sel4_Active return Boolean is (Sel4_Present);

   procedure Send (Dest : Cap_Id; Label : Ipc_Label) is
      Info : constant Unsigned_64 := Msg_Info (Label, 0, 0);
      R : Unsigned_64;
      pragma Unreferenced (Dest);
   begin
      R := Do_Syscall (SEL4_SEND, Info, Unsigned_64 (Dest));
      if R /= 0 then
         Schild_Uart_Driver.Put_Line ("[SE4L] Send error");
      end if;
   end Send;

   procedure Recv (Src : Cap_Id; Out_Label : out Ipc_Label) is
      Info : constant Unsigned_64 := Msg_Info (0, 0, 0);
      R : Unsigned_64;
   begin
      R := Do_Syscall (SEL4_RECV, Info, Unsigned_64 (Src));
      Out_Label := Ipc_Label (R and 16#0FFF_FFFF#);
   end Recv;

   procedure Call (Dest : Cap_Id; Label : Ipc_Label; Reply_Label : out Ipc_Label) is
      Info : constant Unsigned_64 := Msg_Info (Label, 0, 0);
      R : Unsigned_64;
   begin
      R := Do_Syscall (SEL4_CALL, Info, Unsigned_64 (Dest));
      Reply_Label := Ipc_Label (R and 16#0FFF_FFFF#);
   end Call;

   procedure Reply (Dest : Cap_Id) is
      Info : constant Unsigned_64 := Msg_Info (0, 0, 0);
      R : Unsigned_64;
      pragma Unreferenced (Dest);
   begin
      R := Do_Syscall (SEL4_REPLY, Info);
      if R /= 0 then
         Schild_Uart_Driver.Put_Line ("[SE4L] Reply error");
      end if;
   end Reply;

   procedure Wait (Src : Cap_Id; Out_Label : out Ipc_Label) is
      Info : constant Unsigned_64 := Msg_Info (0, 0, 0);
      R : Unsigned_64;
   begin
      R := Do_Syscall (SEL4_NBWAIT, Info, Unsigned_64 (Src));
      Out_Label := Ipc_Label (R and 16#0FFF_FFFF#);
   end Wait;

   procedure Yield is
      R : Unsigned_64;
   begin
      R := Do_Syscall (SEL4_YIELD, 0);
      if R /= 0 and then Sel4_Present then
         Schild_Uart_Driver.Put_Line ("[SE4L] Yield error");
      end if;
   end Yield;

   procedure Retype_Untyped
     (Untyped_Cap   : Cap_Id;
      Target_Type   : Interfaces.Unsigned_64;
      Size_Bits     : Interfaces.Unsigned_32;
      Out_Frame_Cap : out Cap_Id)
   is
      Info : constant Unsigned_64 := Msg_Info (Ipc_Label (Target_Type), 1, Size_Bits);
      R : Unsigned_64;
   begin
      R := Do_Syscall (SEL4_RETYPE, Info, Unsigned_64 (Untyped_Cap));
      Out_Frame_Cap := Cap_Id (R);
   end Retype_Untyped;

   procedure CNode_Mint
     (CNode  : Cap_Id;
      Src    : Cap_Id;
      Dest   : out Cap_Id;
      Rights : Cap_Rights;
      Badge  : Interfaces.Unsigned_64)
   is
      Info : constant Unsigned_64 := Msg_Info (Ipc_Label (Badge), 3, Unsigned_32 (Rights));
      R : Unsigned_64;
      pragma Unreferenced (CNode);
   begin
      R := Do_Syscall (SEL4_CNODE_MINT, Info, Unsigned_64 (Src), Unsigned_64 (CNode));
      Dest := Cap_Id (R);
   end CNode_Mint;

   procedure CNode_Delete
     (CNode : Cap_Id;
      Slot  : Interfaces.Unsigned_64)
   is
      Info : constant Unsigned_64 := Msg_Info (0, 1, 0);
      R : Unsigned_64;
      pragma Unreferenced (CNode);
      pragma Unreferenced (R);
   begin
      R := Do_Syscall (SEL4_CNODE_DELETE, Info, Unsigned_64 (Slot));
   end CNode_Delete;

begin
   Probe_Sel4;
end Schild_Sel4_Ipc;
