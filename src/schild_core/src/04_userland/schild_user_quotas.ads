with Interfaces; use Interfaces;

package Schild_User_Quotas with
  SPARK_Mode => On
is

   type Memory_Quota_Bytes is new Interfaces.Unsigned_64;
   
   type Quota_Passport_Record is record
      Max_Limit     : Memory_Quota_Bytes := 16#0010_0000#; --  Default 1 MiB ceiling.
      Current_Usage : Memory_Quota_Bytes := 0;
      Is_Enforced   : Boolean := True;
   end record;

   procedure Check_And_Update_Quota
     (Passport : in out Quota_Passport_Record;
      Request  : in     Memory_Quota_Bytes;
      Allowed  :    out Boolean)
   with Pre => Passport.Current_Usage <= Passport.Max_Limit,
        Post => (if Allowed then Passport.Current_Usage <= Passport.Max_Limit);

end Schild_User_Quotas;
