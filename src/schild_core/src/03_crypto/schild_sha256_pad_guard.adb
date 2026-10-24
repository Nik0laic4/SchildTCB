pragma Spark_Mode (On);

with Interfaces;
use Interfaces;

package body Schild_Sha256_Pad_Guard is

   procedure Validate_Sha256_Padding
     (Passport     : in     Sha256_Passport_Record;
      Total_Length : in     Unsigned_64;
      Block_Buffer : in     Sha256_Block_Buffer;
      Is_Valid     :    out Boolean)
   is
   begin
      if Passport.Total_Bits_Reported = Total_Length then
         Is_Valid := (Block_Buffer(14) = Unsigned_32(Shift_Right(Total_Length, 32) and 16#FFFF_FFFF#) and then
                      Block_Buffer(15) = Unsigned_32(Total_Length and 16#FFFF_FFFF#));
      else
         Is_Valid := False;
      end if;
   end Validate_Sha256_Padding;

end Schild_Sha256_Pad_Guard;
