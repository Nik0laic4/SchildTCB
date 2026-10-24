package body Schild_Frame_Deallocator with
  SPARK_Mode => On --  Frame deallocation passport.
is

   procedure Safe_Deallocate_Frame
     (Passport : in out Frame_Deallocate_Passport;
      Success  :    out Boolean)
   is
   begin
      --  Mark the frame freed.
      Passport.Is_Freed := True;
      Success           := True;
   end Safe_Deallocate_Frame;

end Schild_Frame_Deallocator;
