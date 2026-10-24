with Interfaces; use Interfaces;

package Schild_Mls_Trusted_Manager with
  SPARK_Mode => On
is
   pragma Elaborate_Body;

   type Privilege_Level_Type is new Interfaces.Unsigned_32 range 0 .. 100;
   -- 100 = Kernel Trusted, 0 = Untrusted Userland

   type Trusted_Passport_Record is record
      PID             : Interfaces.Unsigned_32 := 0;
      Privilege_Level : Privilege_Level_Type := 0;
      Can_Bypass_MAC  : Boolean := False;
   end record;

   procedure Verify_Trust_Authority
     (Passport : in out Trusted_Passport_Record;
      Is_Trusted :    out Boolean)
   with Post => (if Is_Trusted then Passport.Privilege_Level = 100 and Passport.Can_Bypass_MAC);
   --  Trusted authorities run at privilege level 100 and may bypass the MAC.

end Schild_Mls_Trusted_Manager;
