with System.Machine_Code; use System.Machine_Code;

package body Schild_Random_Core with
  SPARK_Mode => Off
is

   -------------------------
   -- Get_Hardware_Random --
   -------------------------
   procedure Get_Hardware_Random
     (Passport : out Random_Passport;
      Success  : out Boolean)
   is
      use type Interfaces.Unsigned_64;
      Val : Interfaces.Unsigned_64 := 0;
      Retry_Count : Natural := 0;
      Hard_Ok : Boolean := False;
   begin
      Passport := (Raw_Value => 0, Is_Hardware_Ok => False, Is_Fresh => False);
      Success  := False;

      --  Issue RDRAND and capture the carry flag as the success indicator.
      --  Volatile: the instruction must not be reordered or elided.
      Asm (Template => "rdrand %0; setc %1",
           Outputs  => (Interfaces.Unsigned_64'Asm_Output ("=r", Val),
                        Boolean'Asm_Output ("=q", Hard_Ok)),
           Volatile => True);

      if Hard_Ok then
         Passport.Raw_Value := Val;
         Passport.Is_Hardware_Ok := True;
         Passport.Is_Fresh := True;
         Success := True;
      end if;

      Asm (Template => "lfence", Volatile => True);
   end Get_Hardware_Random;

end Schild_Random_Core;
