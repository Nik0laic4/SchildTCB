package body Schild_Module_Verifier with
  SPARK_Mode => On
is

   procedure Verify_Module_Integrity
     (Passport : in out Module_Passport_Record;
      Valid    :    out Boolean)
   is
   begin
      --  Authenticate only on an exact digest match.
      if Passport.Computed_Hash = Passport.Expected_Hash then
         Passport.Is_Authentic := True;
         Valid := True;
      else
         Passport.Is_Authentic := False;
         Valid := False;
      end if;
   end Verify_Module_Integrity;

end Schild_Module_Verifier;
