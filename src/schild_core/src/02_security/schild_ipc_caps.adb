pragma Spark_Mode (On);

package body Schild_Ipc_Caps is

   function Has_Send_Capability (Caps : Capability_Mask) return Boolean is
   begin
      return (Caps and CAP_IPC_SEND) /= 0;
   end Has_Send_Capability;

   function Has_Receive_Capability (Caps : Capability_Mask) return Boolean is
   begin
      return (Caps and CAP_IPC_RECEIVE) /= 0;
   end Has_Receive_Capability;

end Schild_Ipc_Caps;
