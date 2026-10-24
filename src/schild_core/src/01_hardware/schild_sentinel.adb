pragma Spark_Mode (On);

package body Schild_Sentinel is

   procedure Inspect_System_State
     (Passport : in     Sentinel_Passport_Record;
      Is_Ok    :    out Boolean)
   is
   begin
      --  Trust only an active, integrity-checked sentinel.
      if Passport.Is_Active and then Passport.Integrity_Checked then
         Is_Ok := True;
      else
         Is_Ok := False;
      end if;
   end Inspect_System_State;

end Schild_Sentinel;
