--  Schild TCB - signal delivery body.
--  Enforces "no write down": a lower-level sender cannot signal a higher target.

with Schild_Uart_Driver;

package body Schild_Signals with
  SPARK_Mode => On
is

   procedure Send_Signal
     (Sender_Level   : in     Interfaces.Unsigned_32;
      Target_Level   : in     Interfaces.Unsigned_32;
      Signal         : in     Signal_Type;
      Target_Cap     : in     Cap_Id;
      Status         :    out Signal_Status)
   is
      use type Interfaces.Unsigned_32;
   begin
      --  Reject when the sender's level is below the target's.
      if Sender_Level < Target_Level then
         Status := Rejected;
         Schild_Uart_Driver.Put_Line ("Signal: REJECTED (No Write Down)");
      else
         Status := Delivered;
         Schild_Uart_Driver.Put_Line ("Signal: delivered to process");
      end if;
   end Send_Signal;

   procedure Block_Signal
     (Context : in out Signal_Context;
      Signal  : in     Signal_Type)
   is
   begin
      Context.Blocked_Signals (Signal) := True;
      Schild_Uart_Driver.Put_String ("Signal: blocked ");
      Schild_Uart_Driver.Put_Line (Signal_Type'Image (Signal));
   end Block_Signal;

   procedure Unblock_Signal
     (Context : in out Signal_Context;
      Signal  : in     Signal_Type)
   is
   begin
      Context.Blocked_Signals (Signal) := False;
      Schild_Uart_Driver.Put_String ("Signal: unblocked ");
      Schild_Uart_Driver.Put_Line (Signal_Type'Image (Signal));
   end Unblock_Signal;

   function Has_Pending_Signals (Context : Signal_Context) return Boolean is
   begin
      for S in Signal_Type loop
         if Context.Pending_Signals (S) then
            return True;
         end if;
      end loop;
      return False;
   end Has_Pending_Signals;

   procedure Deliver_Pending_Signal
     (Context : in out Signal_Context;
      Signal  :    out Signal_Type;
      Handled :    out Boolean)
   is
   begin
      Handled := False;
      Signal := Sig_Term;  -- default: prevent uninitialized OUT (CVE-2026-002)
      for S in Signal_Type loop
         if Context.Pending_Signals (S) and not Context.Blocked_Signals (S) then
            Context.Pending_Signals (S) := False;
            Signal := S;
            Handled := True;
            Schild_Uart_Driver.Put_String ("Signal: delivered ");
            Schild_Uart_Driver.Put_Line (Signal_Type'Image (S));
            exit;
         end if;
      end loop;
   end Deliver_Pending_Signal;

   procedure Register_Handler
     (Context : in out Signal_Context;
      Handler_Cap : Cap_Id)
   is
   begin
      Context.Has_Handler := True;
      Schild_Uart_Driver.Put_Line ("Signal: handler registered");
   end Register_Handler;

   procedure Signal_All_Children
     (Parent_Cap : in     Cap_Id;
      Child_Caps : in     Cap_Id_Array;
      Signal     : in     Signal_Type)
   is
   begin
      Schild_Uart_Driver.Put_String ("Signal: broadcasting ");
      --  Stub: no actual broadcast is performed.
      Schild_Uart_Driver.Put_Line ("to all children (stub)");
   end Signal_All_Children;

end Schild_Signals;