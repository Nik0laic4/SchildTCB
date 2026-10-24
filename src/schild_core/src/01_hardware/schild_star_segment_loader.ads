pragma Spark_Mode (On);

with Interfaces;
use Interfaces; --  Unsigned types for the STAR segment.

package Schild_Star_Segment_Loader is

   type Star_Segment_Passport is record
      Combined_Value : Unsigned_64;
   end record;

   procedure Validate_And_Load_Segment
     (Base_Addr : in     Unsigned_64;
      Passport  :    out Star_Segment_Passport;
      Success   :    out Boolean)
   with
     Global => null,
     Pre    => Base_Addr /= 0,
     Post   => (if Success then Shift_Right (Passport.Combined_Value, 32) = 16#100008#);

end Schild_Star_Segment_Loader;
