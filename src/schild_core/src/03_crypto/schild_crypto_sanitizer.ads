with Interfaces; use Interfaces;

package Schild_Crypto_Sanitizer with
  SPARK_Mode => On
is

   type Crypto_Block_Buffer is array (0 .. 15) of Interfaces.Unsigned_8;

   procedure Purge_Sensitive_Data
     (Buffer : in out Crypto_Block_Buffer)
   with Post => (for all I in Buffer'Range => Buffer(I) = 0);

end Schild_Crypto_Sanitizer;
