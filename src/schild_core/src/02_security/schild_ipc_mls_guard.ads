pragma Spark_Mode (On);

package Schild_Ipc_Mls_Guard is

   --  Four MLS levels.
   type Mls_Level is range 0 .. 3; 

   --  IPC is allowed only between equal levels.
   procedure Verify_Ipc_Mls_Policy
     (Source_Level : in     Mls_Level;
      Target_Level : in     Mls_Level;
      Is_Allowed   :    out Boolean)
   with
     Global  => null,
     Depends => (Is_Allowed => (Source_Level, Target_Level)),
     Post    => (if Is_Allowed then Source_Level = Target_Level
                 else Source_Level /= Target_Level);

end Schild_Ipc_Mls_Guard;
