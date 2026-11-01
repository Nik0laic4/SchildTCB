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
     Post   => Is_Ok = (Passport.Is_Active and Passport.Integrity_Checked);
   --  A sentinel only vouches for the system when it is both active and has
   --  passed its integrity check; either failure means "not OK".

end Schild_Sentinel;
