with Schild_Random_Core; use Schild_Random_Core;

package body Schild_Rng_Manager with
  SPARK_Mode => Off --  Hardware primitive; the RDRAND asm lives in Schild_Random_Core.
is

   procedure Gather_Hardware_Entropy
     (Entropy_Out :    out Crypto_Entropy_64;
      Success     :    out Boolean)
   is
      Draw : Random_Passport;
   begin
      Entropy_Out := 0;
      Success     := False;

      --  Draw one 64-bit word from the on-CPU hardware RNG (RDRAND).
      --  The asm primitive is Schild_Random_Core.Get_Hardware_Random
      --  (single source of truth for the RDRAND instruction).
      Get_Hardware_Random (Passport => Draw, Success => Success);

      if Success then
         Entropy_Out := Crypto_Entropy_64 (Draw.Raw_Value);
      end if;
   end Gather_Hardware_Entropy;

end Schild_Rng_Manager;
