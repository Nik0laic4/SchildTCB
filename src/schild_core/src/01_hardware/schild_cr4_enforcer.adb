pragma Spark_Mode (On);

package body Schild_Cr4_Enforcer is

   procedure Enforce_Cr4_Security_Policy
     (Old_Cr4 : in     Cr4_Register_64;
      New_Cr4 : in     Cr4_Register_64;
      Is_Safe :    out Boolean)
   is
      Smep_Active : Boolean;
      Smap_Active : Boolean;
      Pae_Stable  : Boolean;
   begin
      Smep_Active := (New_Cr4 and CR4_SMEP_BIT) /= 0;
      Smap_Active := (New_Cr4 and CR4_SMAP_BIT) /= 0;
      Pae_Stable  := (New_Cr4 and CR4_PAE_BIT) = (Old_Cr4 and CR4_PAE_BIT);

      Is_Safe := Smep_Active and Smap_Active and Pae_Stable;
   end Enforce_Cr4_Security_Policy;

end Schild_Cr4_Enforcer;
