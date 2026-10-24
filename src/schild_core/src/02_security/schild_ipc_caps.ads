pragma Spark_Mode (On);

package Schild_Ipc_Caps is

   --  Capability bits for send and receive.
   CAP_IPC_SEND    : constant := 16#0000_0001#;
   CAP_IPC_RECEIVE : constant := 16#0000_0002#;

   type Capability_Mask is mod 2**32;

   --  True when the send capability bit is set.
   function Has_Send_Capability (Caps : Capability_Mask) return Boolean
   with
     Global => null,
     Post   => Has_Send_Capability'Result = ((Caps and CAP_IPC_SEND) /= 0);

   --  True when the receive capability bit is set.
   function Has_Receive_Capability (Caps : Capability_Mask) return Boolean
   with
     Global => null,
     Post   => Has_Receive_Capability'Result = ((Caps and CAP_IPC_RECEIVE) /= 0);

end Schild_Ipc_Caps;
