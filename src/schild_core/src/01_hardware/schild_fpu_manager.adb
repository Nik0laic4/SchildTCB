pragma Spark_Mode (On);

package body Schild_Fpu_Manager is

   procedure Save_Fpu_Context
     (Passport : in out Fpu_State_Passport;
      Success  :    out Boolean)
   is
   begin
      if Passport.Is_Aligned then
         Passport.Is_Saved := True;
         Success           := True;
      else
         Success           := False;
      end if;
   end Save_Fpu_Context;

   procedure Restore_Fpu_Context
     (Passport : in out Fpu_State_Passport;
      Success  :    out Boolean)
   is
   begin
      if Passport.Is_Saved then
         Passport.Is_Saved := False;
         Success           := True;
      else
         Success           := False;
      end if;
   end Restore_Fpu_Context;

end Schild_Fpu_Manager;
