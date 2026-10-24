pragma Spark_Mode (On);

package body Schild_Ipc_Compartment_Guard is

   procedure Verify_Compartment_Access
     (Source_Mask : in     Compartment_Mask;
      Target_Mask : in     Compartment_Mask;
      Is_Allowed  :    out Boolean)
   is
   begin
      --  Allow only when the target's compartments contain the source's.
      Is_Allowed := (Source_Mask and Target_Mask) = Source_Mask;
   end Verify_Compartment_Access;

end Schild_Ipc_Compartment_Guard;
