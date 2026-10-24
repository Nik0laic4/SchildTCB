package body Schild_Mls_Ipc_Gateway with
  SPARK_Mode => On --  IPC across levels requires equal clearance.
is

   procedure Authorize_Ipc_Transfer
     (Sender_Level   : in     Clear_Level_Type;
      Receiver_Level : in     Clear_Level_Type;
      Status         :    out Gateway_Status)
   is
   begin
      --  Grant only same-level transfers.
      if Sender_Level = Receiver_Level then
         Status := Access_Granted;
      else
         Status := Access_Denied;
      end if;
   end Authorize_Ipc_Transfer;

end Schild_Mls_Ipc_Gateway;
