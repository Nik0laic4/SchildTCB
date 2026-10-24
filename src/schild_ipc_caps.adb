with System.Machine_Code; use System.Machine_Code;

package body Schild_Ipc_Caps with
  SPARK_Mode => On
is

   ------------------------
   -- Authorize_Ipc_Send --
   ------------------------
   procedure Authorize_Ipc_Send
     (Registry   : in Ipc_Capability_Registry;
      PID        : in Schild_User_Space.Process_Id_Type;
      Mailbox    : in Mailbox_Id_Range;
      Is_Allowed : out Boolean)
   is
      use type Interfaces.Unsigned_32;
   begin
      Is_Allowed := False;

      --  Fence before the capability check.
      Asm (Template => "lfence", Volatile => True);

      if Registry (PID, Mailbox).Is_Registered then
         --  Check the send capability bit.
         if (Registry (PID, Mailbox).Mailbox_Mask and Cap_Ipc_Send) = Cap_Ipc_Send then
            Is_Allowed := True;
         end if;
      end if;

      Asm (Template => "lfence", Volatile => True);
   end Authorize_Ipc_Send;

   ---------------------------
   -- Authorize_Ipc_Receive --
   ---------------------------
   procedure Authorize_Ipc_Receive
     (Registry   : in Ipc_Capability_Registry;
      PID        : in Schild_User_Space.Process_Id_Type;
      Mailbox    : in Mailbox_Id_Range;
      Is_Allowed : out Boolean)
   is
      use type Interfaces.Unsigned_32;
   begin
      Is_Allowed := False;

      Asm (Template => "lfence", Volatile => True);

      if Registry (PID, Mailbox).Is_Registered then
         --  Check the receive capability bit.
         if (Registry (PID, Mailbox).Mailbox_Mask and Cap_Ipc_Receive) = Cap_Ipc_Receive then
            Is_Allowed := True;
         end if;
      end if;

      Asm (Template => "lfence", Volatile => True);
   end Authorize_Ipc_Receive;

end Schild_Ipc_Caps;
