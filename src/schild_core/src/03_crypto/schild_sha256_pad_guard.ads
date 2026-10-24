pragma Spark_Mode (On);

with Interfaces; 
use Interfaces; --  Unsigned_32/Unsigned_64 for the length words and shifts.

package Schild_Sha256_Pad_Guard is

   type Sha256_Block_Buffer is array (0 .. 15) of Unsigned_32;

   type Sha256_Passport_Record is record
      Total_Bits_Reported : Unsigned_64;
   end record;

   procedure Validate_Sha256_Padding
     (Passport     : in     Sha256_Passport_Record;
      Total_Length : in     Unsigned_64;
      Block_Buffer : in     Sha256_Block_Buffer;
      Is_Valid     :    out Boolean)
   with
     Global => null,
     Post   => Is_Valid = (Passport.Total_Bits_Reported = Total_Length and then
                            Block_Buffer(14) = Unsigned_32(Shift_Right(Total_Length, 32) and 16#FFFF_FFFF#) and then
                            Block_Buffer(15) = Unsigned_32(Total_Length and 16#FFFF_FFFF#));

end Schild_Sha256_Pad_Guard;
