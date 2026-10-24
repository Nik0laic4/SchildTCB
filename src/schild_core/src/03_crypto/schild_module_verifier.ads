with Interfaces; use Interfaces;

package Schild_Module_Verifier with
  SPARK_Mode => On
is
   pragma Elaborate_Body;

   type Sha256_Hash is array (1 .. 32) of Interfaces.Unsigned_8;
   
   type Module_Passport_Record is record
      Computed_Hash : Sha256_Hash := (others => 0);
      Expected_Hash : Sha256_Hash := (others => 0);
      Is_Authentic  : Boolean := False;
   end record;

   procedure Verify_Module_Integrity
     (Passport : in out Module_Passport_Record;
      Valid    :    out Boolean)
   with Post => (if Valid then Passport.Is_Authentic 
                 and Passport.Computed_Hash = Passport.Expected_Hash);
   --  Compares a freshly computed image hash against the expected value.

end Schild_Module_Verifier;
