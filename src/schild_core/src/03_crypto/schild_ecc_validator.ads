pragma Spark_Mode (On);

with Interfaces;
use Interfaces;

package Schild_Ecc_Validator is

   type Ecc_Coordinate_Array is array (1 .. 8) of Unsigned_32;

   type Ecc_Point_Passport is record
      Coord_X    : Ecc_Coordinate_Array;
      Coord_Y    : Ecc_Coordinate_Array;
      Is_On_Curve: Boolean;
   end record;

   procedure Validate_Ecc_Point
     (Point   : in out Ecc_Point_Passport;
      Success :    out Boolean)
   with
     Global => null,
     Post   => (if Success then Point.Is_On_Curve = True);

end Schild_Ecc_Validator;
