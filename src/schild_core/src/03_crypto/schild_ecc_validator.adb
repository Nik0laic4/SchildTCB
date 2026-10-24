pragma Spark_Mode (On);

package body Schild_Ecc_Validator is

   procedure Validate_Ecc_Point
     (Point   : in out Ecc_Point_Passport;
      Success :    out Boolean)
   is
   begin
      --  A real on-curve check (y^2 = x^3 + ax + b mod p) requires the curve
      --  parameters, which are not part of this passport. Fail closed: do not
      --  accept an unverified point as on-curve.
      Point.Is_On_Curve := False;
      Success           := False;
   end Validate_Ecc_Point;

end Schild_Ecc_Validator;
