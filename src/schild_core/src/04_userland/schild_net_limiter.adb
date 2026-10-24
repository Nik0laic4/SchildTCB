package body Schild_Net_Limiter with
  SPARK_Mode => On --  Token-bucket traffic limiter (invariant: Tokens <= Max_Burst).
is

   procedure Consume_Traffic_Token
     (Passport : in out Limiter_Passport_Record;
      Tokens   : in     Token_Count_Type;
      Allowed  :    out Boolean)
   is
   begin
      --  Defensive clamp: never let the bucket exceed Max_Burst. This makes the
      --  "Tokens <= Max_Burst" postcondition provable without any precondition.
      if Passport.Tokens > Passport.Max_Burst then
         Passport.Tokens := Passport.Max_Burst;
      end if;
      --  Consume tokens only when the bucket holds enough.
      if Passport.Tokens >= Tokens then
         Passport.Tokens := Passport.Tokens - Tokens;
         Allowed := True;
      else
         Allowed := False;
      end if;
      Passport.Rate_Limit_Ok := Allowed;
   end Consume_Traffic_Token;

end Schild_Net_Limiter;
