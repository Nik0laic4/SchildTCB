pragma Spark_Mode (On);

package body Schild_Segment_Calculator is

   procedure Validate_User_Segments
     (Passport   : in     Segment_Passport_Record;
      Is_Trusted :    out Boolean)
   is
   begin
      if (Passport.Secure_Cs and 16#03#) = Rpl_User_Mask and then
         (Passport.Secure_Ss and 16#03#) = Rpl_User_Mask
      then
         Is_Trusted := (Passport.Secure_Cs = (Gdt_User_Code_Slot or Rpl_User_Mask) and then
                        Passport.Secure_Ss = (Gdt_User_Data_Slot or Rpl_User_Mask));
      else
         Is_Trusted := False;
      end if;
   end Validate_User_Segments;

end Schild_Segment_Calculator;
