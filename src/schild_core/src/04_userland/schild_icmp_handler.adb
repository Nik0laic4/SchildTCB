package body Schild_Icmp_Handler with
  SPARK_Mode => Off --  Scaffold: answers with an ICMP echo reply.
is

   procedure Process_Icmp_Echo
     (Raw_Len   : in     Interfaces.Unsigned_32;
      Passport  :    out Icmp_Passport_Record;
      Success   :    out Boolean)
   is
   begin
      --  Reply with ICMP type 0 (echo reply).
      Passport.Icmp_Type := 0; -- Echo Reply
      Passport.Is_Valid  := True;
      Success            := True;
   end Process_Icmp_Echo;

end Schild_Icmp_Handler;
