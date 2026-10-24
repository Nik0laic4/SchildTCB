pragma Spark_Mode (On);

with Interfaces;
use Interfaces;

package Schild_Rng_Manager is

   type Crypto_Entropy_64 is mod 2**64;

   procedure Gather_Hardware_Entropy
     (Entropy_Out :    out Crypto_Entropy_64;
      Success     :    out Boolean)
   with
     Global => null;

end Schild_Rng_Manager;
