with Interfaces;
with Schild_Mls_Core_Engine; use Schild_Mls_Core_Engine;
use type Interfaces.Unsigned_32;

package Schild_Mls_Cache_Flush with
  SPARK_Mode => On
is
   pragma Elaborate_Body;

   type Cache_Flush_Passport is record
      Old_Level : Clear_Level_Type := 1;
      New_Level : Clear_Level_Type := 1;
      Is_Flushed : Boolean := False;
   end record;

   procedure Execute_Safe_Transition
     (Passport : in out Cache_Flush_Passport;
      Success  :    out Boolean)
   with Post => (if Success and Passport.New_Level < Passport.Old_Level 
                 then Passport.Is_Flushed);
   --  A successful downgrade must flush the cache.

end Schild_Mls_Cache_Flush;
