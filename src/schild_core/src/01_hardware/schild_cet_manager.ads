pragma Spark_Mode (On);

with Interfaces;
use Interfaces;

package Schild_Cet_Manager is

   type Cet_Passport_Record is record
      Is_Shadow_Stack_Active : Boolean;
      Is_Ib_Tracking_Active  : Boolean;
   end record;

   procedure Activate_Cet_Protection
     (Sstk_Base : in     Unsigned_64;
      Passport  :    out Cet_Passport_Record;
      Success   :    out Boolean)
   with
     Global => null,
     Pre    => sstk_Base /= 0 and then (Sstk_Base and 16#7#) = 0,
     Post   => (if Success then Passport.Is_Shadow_Stack_Active = True);

end Schild_Cet_Manager;
