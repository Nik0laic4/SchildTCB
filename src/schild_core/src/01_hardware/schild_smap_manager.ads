pragma Spark_Mode (On);

package Schild_Smap_Manager is

   type Smap_Passport_Record is record
      Is_Access_Blocked : Boolean;
   end record;

   procedure Enable_Smap_Protection
     (Passport : out Smap_Passport_Record;
      Success  : out Boolean)
   with
     Global => null,
     Post   => (if Success then Passport.Is_Access_Blocked = True);

   procedure Disable_Smap_Protection
     (Passport : out Smap_Passport_Record;
      Success  : out Boolean)
   with
     Global => null,
     Post   => (if Success then Passport.Is_Access_Blocked = False);

end Schild_Smap_Manager;
