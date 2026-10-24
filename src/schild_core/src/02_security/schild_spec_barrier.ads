pragma Spark_Mode (On);

package Schild_Spec_Barrier is

   type Barrier_Passport_Record is record
      Is_Fence_Active : Boolean;
   end record;

   procedure Enforce_Speculative_Barrier
     (Passport : out Barrier_Passport_Record;
      Success  : out Boolean)
   with
     Global => null,
     Post   => (if Success then Passport.Is_Fence_Active = True);

end Schild_Spec_Barrier;
