with Interfaces;
with Schild_User_Space;

package Schild_Ipc_Caps with
  SPARK_Mode => On
is

   --  64 mailboxes per process.
   subtype Mailbox_Id_Range is Natural range 1 .. 64;

   --  Bitmask of IPC capabilities (send/receive).
   subtype Ipc_Capability_Type is Interfaces.Unsigned_32;

   Cap_Ipc_Send    : constant Interfaces.Unsigned_32 := 16#01#;
   Cap_Ipc_Receive : constant Interfaces.Unsigned_32 := 16#02#;

   --  A process's rights for one mailbox.
   type Process_Ipc_Rights_Record is record
      Mailbox_Mask : Ipc_Capability_Type;
      Is_Registered : Boolean;
   end record;

   --  The per-process, per-mailbox registry.
   type Ipc_Capability_Registry is array (Schild_User_Space.Process_Id_Type, Mailbox_Id_Range) of Process_Ipc_Rights_Record;

   --  Allow a send when the send bit is set.
   procedure Authorize_Ipc_Send
     (Registry   : in Ipc_Capability_Registry;
      PID        : in Schild_User_Space.Process_Id_Type;
      Mailbox    : in Mailbox_Id_Range;
      Is_Allowed : out Boolean)
   with
     Pre  => PID > 0,
     --  The mailbox must be registered and the send bit set.
     Post => (if Is_Allowed then 
                Registry (PID, Mailbox).Is_Registered 
                and (Registry (PID, Mailbox).Mailbox_Mask and Cap_Ipc_Send) = Cap_Ipc_Send);

   --  Allow a receive when the receive bit is set.
   procedure Authorize_Ipc_Receive
     (Registry   : in Ipc_Capability_Registry;
      PID        : in Schild_User_Space.Process_Id_Type;
      Mailbox    : in Mailbox_Id_Range;
      Is_Allowed : out Boolean)
   with
     Pre  => PID > 0,
     --  The mailbox must be registered and the receive bit set.
     Post => (if Is_Allowed then 
                Registry (PID, Mailbox).Is_Registered 
                and (Registry (PID, Mailbox).Mailbox_Mask and Cap_Ipc_Receive) = Cap_Ipc_Receive);

end Schild_Ipc_Caps;
