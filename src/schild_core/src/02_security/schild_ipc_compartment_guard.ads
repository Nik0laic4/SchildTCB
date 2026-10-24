pragma Spark_Mode (On);

package Schild_Ipc_Compartment_Guard is

   --  Bitmask of the compartments a capability belongs to.
   type Compartment_Mask is mod 2**32;

   --  A transfer is allowed only when the source's compartments are a subset
   --  of the target's (the target dominates the source).
   procedure Verify_Compartment_Access
     (Source_Mask : in     Compartment_Mask;
      Target_Mask : in     Compartment_Mask;
      Is_Allowed  :    out Boolean)
   with
     Global  => null,
     Depends => (Is_Allowed => (Source_Mask, Target_Mask)),
     Post    => (if Is_Allowed then (Source_Mask and Target_Mask) = Source_Mask
                 else (Source_Mask and Target_Mask) /= Source_Mask);

end Schild_Ipc_Compartment_Guard;
