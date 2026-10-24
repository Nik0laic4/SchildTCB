with System.Machine_Code; use System.Machine_Code;

package body Schild_Aes_Ni_Core with
  SPARK_Mode => On
is

   --------------------------
   -- Encrypt_Single_Round --
   --------------------------
   procedure Encrypt_Single_Round
     (State    : in out Aes_Block_Type;
      Round_Key: in Aes_Block_Type;
      Passport : out Aes_Ni_Passport;
      Success  : out Boolean)
   is
   begin
      --  Start from a failed passport.
      Passport := (Is_Hardware_Accelerated => False, Is_Aligned => False, Is_Sealed => False);
      Success  := False;

      --  Fence before touching AES-NI state.
      Asm (Template => "lfence", Volatile => True);

      --  Require 16-byte alignment of both buffers.
      if State'Address mod 16 = 0 and Round_Key'Address mod 16 = 0 then
         
         --  Run one AES-NI round (aesenc).
         Asm (Template => "aesenc %1, %0",
              Outputs  => Aes_Block_Type'Asm_Output ("+x", State),
              Inputs   => Aes_Block_Type'Asm_Input ("x", Round_Key),
              Volatile => True);

         Passport.Is_Hardware_Accelerated := True;
         Passport.Is_Aligned              := True;
         Passport.Is_Sealed               := True;
         Success                          := True;
      end if;

      Asm (Template => "lfence", Volatile => True);
   end Encrypt_Single_Round;

end Schild_Aes_Ni_Core;
