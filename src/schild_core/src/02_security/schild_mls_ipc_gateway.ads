with Interfaces;
with Schild_Mls_Core_Engine; use Schild_Mls_Core_Engine;
use type Interfaces.Unsigned_32;

package Schild_Mls_Ipc_Gateway with
  SPARK_Mode => On
is
   pragma Elaborate_Body;

   type Gateway_Status is (Access_Denied, Access_Granted, Security_Fault);

   procedure Authorize_Ipc_Transfer
     (Sender_Level   : in     Clear_Level_Type;
      Receiver_Level : in     Clear_Level_Type;
      Status         :    out Gateway_Status)
   with Post => (if Status = Access_Granted then Sender_Level = Receiver_Level);
   --  Grant only equal-clearance transfers.

end Schild_Mls_Ipc_Gateway;
