pragma Spark_Mode (On);

package Schild_Cr4_Enforcer is

   type Cr4_Register_64 is mod 2**64;

   --  CR4 bits guarded by the security policy.
   CR4_PAE_BIT  : constant Cr4_Register_64 := 16#0000_0020#; --  Physical Address Extension.
   CR4_SMEP_BIT : constant Cr4_Register_64 := 16#0010_0000#; --  Supervisor Mode Execution Prevention.
   CR4_SMAP_BIT : constant Cr4_Register_64 := 16#0020_0000#; --  Supervisor Mode Access Prevention.

   --  SMEP/SMAP must stay set and PAE unchanged.
   procedure Enforce_Cr4_Security_Policy
     (Old_Cr4 : in     Cr4_Register_64;
      New_Cr4 : in     Cr4_Register_64;
      Is_Safe :    out Boolean)
   with
     Global  => null,
     Depends => (Is_Safe => (Old_Cr4, New_Cr4)),
     Post    => (if Is_Safe then
                   (New_Cr4 and CR4_SMEP_BIT) /= 0 and
                   (New_Cr4 and CR4_SMAP_BIT) /= 0 and
                   (New_Cr4 and CR4_PAE_BIT) = (Old_Cr4 and CR4_PAE_BIT)
                 else
                   (New_Cr4 and CR4_SMEP_BIT) = 0 or
                   (New_Cr4 and CR4_SMAP_BIT) = 0 or
                   (New_Cr4 and CR4_PAE_BIT) /= (Old_Cr4 and CR4_PAE_BIT));

end Schild_Cr4_Enforcer;
