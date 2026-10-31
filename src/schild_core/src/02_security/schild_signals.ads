--  Schild TCB - POSIX-style signals with MLS-gated delivery.
--  Pending/blocked signal sets plus delivery status; sending is rejected when
--  the sender's level is below the target's.

with Interfaces;
with Schild_Sel4_Ipc;

package Schild_Signals with
  SPARK_Mode => On
is
   pragma Elaborate_Body;

   use Schild_Sel4_Ipc;
   use type Interfaces.Unsigned_32;

   type Cap_Id_Array is array (Positive range <>) of Cap_Id;

   --  The supported signal kinds.
   type Signal_Type is (Sig_Term, Sig_Kill, Sig_Int, Sig_Hup, Sig_Child);
   type Signal_Set is array (Signal_Type) of Boolean;

   --  Per-process signal state: pending and blocked sets.
   type Signal_Context is record
      Pending_Signals : Signal_Set := [others => False];
      Blocked_Signals : Signal_Set := [others => False];
      Has_Handler     : Boolean := False;
   end record;

   --  Outcome of a signal-send operation.
   type Signal_Status is (Delivered, Pending, Blocked, Rejected);

   ------------------------------------------------------------
   --  Signal operations.
   ------------------------------------------------------------

   --  Send a signal, enforcing the MLS level rule.
   procedure Send_Signal
     (Sender_Level   : in     Interfaces.Unsigned_32;
      Target_Level   : in     Interfaces.Unsigned_32;
      Signal         : in     Signal_Type;
      Target_Cap     : in     Cap_Id;
      Status         :    out Signal_Status)
   with
     Pre  => Target_Cap /= Null_Cap,
     Post => (if Sender_Level < Target_Level then Status = Rejected
              else Status = Delivered);
     --  No write down: a lower-level sender may not signal a higher target.

   --  Add a signal to the blocked set.
   procedure Block_Signal
     (Context : in out Signal_Context;
      Signal  : in     Signal_Type)
   with
     Post => Context.Blocked_Signals (Signal) = True;

   --  Remove a signal from the blocked set.
   procedure Unblock_Signal
     (Context : in out Signal_Context;
      Signal  : in     Signal_Type)
   with
     Post => Context.Blocked_Signals (Signal) = False;

   --  True when at least one signal is pending.
   function Has_Pending_Signals (Context : Signal_Context) return Boolean
   with Post => Has_Pending_Signals'Result =
                (for some S in Signal_Type => Context.Pending_Signals (S));

   --  Dequeue and deliver one pending signal.
   procedure Deliver_Pending_Signal
     (Context : in out Signal_Context;
      Signal  :    out Signal_Type;
      Handled :    out Boolean)
   with Post => (if Handled then
                   Context.Pending_Signals (Signal) = False
                     and Context'Old.Pending_Signals (Signal)
                     and not Context'Old.Blocked_Signals (Signal));

   --  Register a handler capability for delivered signals.
   procedure Register_Handler
     (Context : in out Signal_Context;
      Handler_Cap : Cap_Id)
   with
     Post => Context.Has_Handler = True;

   --  Send a signal to every child capability.
   procedure Signal_All_Children
     (Parent_Cap : in     Cap_Id;
      Child_Caps : in     Cap_Id_Array;
      Signal     : in     Signal_Type);

end Schild_Signals;