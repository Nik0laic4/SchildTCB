pragma Spark_Mode (On);

with Interfaces;
use Interfaces;

package body Schild_Star_Segment_Loader is

   procedure Validate_And_Load_Segment
     (Base_Addr : in     Unsigned_64;
      Passport  :    out Star_Segment_Passport;
      Success   :    out Boolean)
   is
   begin
      if Base_Addr /= 0 then
         --  Combine a fixed base with the low 32 bits of Base_Addr.
         Passport.Combined_Value := Shift_Left (16#100008#, 32) or (Base_Addr and 16#FFFF_FFFF#);
         Success                 := True;
      else
         Passport := (Combined_Value => 0);
         Success  := False;
      end if;
   end Validate_And_Load_Segment;

end Schild_Star_Segment_Loader;
