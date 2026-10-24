pragma Spark_Mode (On);

package Schild_Sentinel is

   type Sentinel_Passport_Record is record
      Is_Active         : Boolean;
      Integrity_Checked : Boolean;
   end record;

   procedure Inspect_System_State
     (Passport : in     Sentinel_Passport_Record;
      Is_Ok    :    out Boolean)
   with
     Global => null,
     Pre    => Passport.Is_Active = True;

end Schild_Sentinel;
