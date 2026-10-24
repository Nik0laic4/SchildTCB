pragma Spark_Mode (On);

package Schild_Fpu_Manager is

   type Fpu_State_Passport is record
      Is_Saved   : Boolean;
      Is_Aligned : Boolean;
   end record;

   procedure Save_Fpu_Context
     (Passport : in out Fpu_State_Passport;
      Success  :    out Boolean)
   with
     Global => null,
     Post   => (if Success then Passport.Is_Saved = True);

   procedure Restore_Fpu_Context
     (Passport : in out Fpu_State_Passport;
      Success  :    out Boolean)
   with
     Global => null,
     Pre    => Passport.Is_Saved = True,
     Post   => (if Success then Passport.Is_Saved = False);

end Schild_Fpu_Manager;
