package body Schild_Mls_Trusted_Manager with
  SPARK_Mode => On --  Only PID 1/2 (root/init) may bypass the MAC.
is

   procedure Verify_Trust_Authority
     (Passport : in out Trusted_Passport_Record;
      Is_Trusted :    out Boolean)
   is
   begin
      --  Root and init are the trusted authorities.
      if Passport.PID = 1 or Passport.PID = 2 then
         Passport.Privilege_Level := 100;
         Passport.Can_Bypass_MAC  := True;
         Is_Trusted              := True;
      else
         Passport.Privilege_Level := 0;
         Passport.Can_Bypass_MAC  := False;
         Is_Trusted              := False;
      end if;
   end Verify_Trust_Authority;

end Schild_Mls_Trusted_Manager;
