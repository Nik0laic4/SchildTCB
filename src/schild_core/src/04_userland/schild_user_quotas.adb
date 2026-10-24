package body Schild_User_Quotas with
  SPARK_Mode => Off --  Memory quota enforcement (usage must stay under the limit).
is

   procedure Check_And_Update_Quota
     (Passport : in out Quota_Passport_Record;
      Request  : in     Memory_Quota_Bytes;
      Allowed  :    out Boolean)
   is
   begin
      --  Admit the request only if it fits within the remaining quota.
      if Passport.Current_Usage + Request <= Passport.Max_Limit then
         Passport.Current_Usage := Passport.Current_Usage + Request;
         Allowed := True;
      else
         Allowed := False;
      end if;
   end Check_And_Update_Quota;

end Schild_User_Quotas;
