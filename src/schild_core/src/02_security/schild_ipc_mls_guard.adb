pragma Spark_Mode (On);

package body Schild_Ipc_Mls_Guard is

   procedure Verify_Ipc_Mls_Policy
     (Source_Level : in     Mls_Level;
      Target_Level : in     Mls_Level;
      Is_Allowed   :    out Boolean)
   is
   begin
      --  Allow only equal-level IPC.
      Is_Allowed := (Source_Level = Target_Level);
   end Verify_Ipc_Mls_Policy;

end Schild_Ipc_Mls_Guard;
