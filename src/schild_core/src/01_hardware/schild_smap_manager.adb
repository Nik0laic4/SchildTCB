pragma Spark_Mode (On);

package body Schild_Smap_Manager is

   procedure Enable_Smap_Protection
     (Passport : out Smap_Passport_Record;
      Success  : out Boolean)
   is
   begin
      --  Enable SMAP (block user access).
      Passport.Is_Access_Blocked := True;
      Success                    := True;
   end Enable_Smap_Protection;

   procedure Disable_Smap_Protection
     (Passport : out Smap_Passport_Record;
      Success  : out Boolean)
   is
   begin
      --  Disable SMAP (allow access).
      Passport.Is_Access_Blocked := False;
      Success                    := True;
   end Disable_Smap_Protection;

end Schild_Smap_Manager;
