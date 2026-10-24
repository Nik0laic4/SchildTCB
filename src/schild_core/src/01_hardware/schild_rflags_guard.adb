pragma Spark_Mode (On);

with Interfaces;
use Interfaces;

package body Schild_Rflags_Guard is

   procedure Validate_Cpu_Flags
     (Passport   : in     Rflags_Passport_Record;
      Is_Trusted :    out Boolean)
   is
   begin
      --  Trust only when IOPL is clear and IOPL bits are unset.
      Is_Trusted := ((Passport.Computed_Value and Rflags_Mask_Iopl) = 0
                     and then (Passport.Computed_Value and Rflags_Bit_Interrupt) /= 0);
   end Validate_Cpu_Flags;

end Schild_Rflags_Guard;
