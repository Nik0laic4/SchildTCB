package body Schild_Stack_Sanitizer with
  SPARK_Mode => Off --  Scaffold: marks the stack as sanitized.
is

   procedure Sanitize_And_Randomize_Stack
     (Passport : in out Sanitizer_Passport_Record;
      Success  :    out Boolean)
   is
   begin
      --  Scaffold: no stack bytes are actually cleared.
      Passport.Is_Sanitized := True;
      Success := True;
   end Sanitize_And_Randomize_Stack;

end Schild_Stack_Sanitizer;
