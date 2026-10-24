pragma Spark_Mode (On);

with Interfaces;
use Interfaces; --  Unsigned_64 for RFLAGS masks.

package Schild_Rflags_Guard is

   Rflags_Mask_Iopl     : constant Unsigned_64 := 16#0000_0000_0000_3000#;
   Rflags_Bit_Interrupt : constant Unsigned_64 := 16#0000_0000_0000_0200#;

   type Rflags_Passport_Record is record
      Computed_Value : Unsigned_64;
   end record;

   procedure Validate_Cpu_Flags
     (Passport   : in     Rflags_Passport_Record;
      Is_Trusted :    out Boolean)
   with
     Global => null,
     Post   => Is_Trusted = ((Passport.Computed_Value and Rflags_Mask_Iopl) = 0
                             and (Passport.Computed_Value and Rflags_Bit_Interrupt) /= 0);

end Schild_Rflags_Guard;
