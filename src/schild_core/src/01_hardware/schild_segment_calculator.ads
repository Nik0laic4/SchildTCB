pragma Spark_Mode (On);

with Interfaces; 
use Interfaces;

package Schild_Segment_Calculator is

   Rpl_User_Mask     : constant Unsigned_16 := 16#0003#;
   Gdt_User_Code_Slot : constant Unsigned_16 := 16#001B#;
   Gdt_User_Data_Slot : constant Unsigned_16 := 16#0023#;

   type Segment_Passport_Record is record
      Secure_Cs : Unsigned_16;
      Secure_Ss : Unsigned_16;
   end record;

   procedure Validate_User_Segments
     (Passport   : in     Segment_Passport_Record;
      Is_Trusted :    out Boolean)
   with
     Global => null,
     Pre    => (Passport.Secure_Cs and 16#03#) = Rpl_User_Mask and then
               (Passport.Secure_Ss and 16#03#) = Rpl_User_Mask,
     Post   => Is_Trusted = (Passport.Secure_Cs = (Gdt_User_Code_Slot or Rpl_User_Mask) and then
                             Passport.Secure_Ss = (Gdt_User_Data_Slot or Rpl_User_Mask));

end Schild_Segment_Calculator;
