pragma Spark_Mode (On);

with Interfaces;
use Interfaces;

package Schild_Aes_Ni_Core is

   subtype Aes_Block_Index is Integer range 0 .. 15;
   type Aes_Block_Type is array (Aes_Block_Index) of Unsigned_8;

   --  AES-128 (FIPS-197): encrypt a single 16-byte block with a 16-byte key.
   --  Software implementation (portable, no AES-NI dependency); the S-box and
   --  10-round transform are outside the SPARK Level-4 gate (SPARK_Mode => Off
   --  in the body).
   procedure Encrypt_Aes128_Block
     (Plaintext  : in     Aes_Block_Type;
      Key        : in     Aes_Block_Type;
      Ciphertext :    out Aes_Block_Type)
   with Global => null;

end Schild_Aes_Ni_Core;
