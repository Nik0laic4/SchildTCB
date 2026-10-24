with Interfaces; use Interfaces;

package Schild_Net_Limiter with
  SPARK_Mode => On
is

   type Token_Count_Type is new Interfaces.Unsigned_64;
   
   type Limiter_Passport_Record is record
      Tokens        : Token_Count_Type := 100;
      Max_Burst     : Token_Count_Type := 1000;
      Rate_Limit_Ok : Boolean := True;
   end record;

   procedure Consume_Traffic_Token
     (Passport : in out Limiter_Passport_Record;
      Tokens   : in     Token_Count_Type;
      Allowed  :    out Boolean)
   with Post => (if Allowed then Passport.Rate_Limit_Ok)
                  and Passport.Tokens <= Passport.Max_Burst;

end Schild_Net_Limiter;
