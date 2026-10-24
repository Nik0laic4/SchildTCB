package body Schild_Mls_Cache_Flush with
  SPARK_Mode => On --  Flush cache on declassification (level drop).
is

   procedure Execute_Safe_Transition
     (Passport : in out Cache_Flush_Passport;
      Success  :    out Boolean)
   is
   begin
      --  A downward transition (declassification) requires a cache flush.
      if Passport.New_Level < Passport.Old_Level then
         --  Mark the cache flushed.
         Passport.Is_Flushed := True;
      else
         Passport.Is_Flushed := False;
      end if;

      Success := True;
   end Execute_Safe_Transition;

end Schild_Mls_Cache_Flush;
