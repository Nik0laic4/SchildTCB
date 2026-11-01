pragma Spark_Mode (On);

with Interfaces;
use Interfaces;

--  SCAFFOLD (2026-11-01): this is NOT a real SHA-256. `Compute_Sha_Digest`
--  returns a placeholder magic value, not a digest of `Buffer`. The real SHA-256
--  compression is `Schild_HMAC_SHA256` (body Off, KAT-validated). Neither this
--  package nor its former consumer `Schild_Audit_Chainer` is wired into the live
--  audit path (`Schild_Audit_Logger` persists events without chaining them).
package Schild_Sha_Manager is

   type Sha_Digest_Array is array (1 .. 8) of Unsigned_32;
   type Sha_Block_Buffer_Array is array (0 .. 15) of Unsigned_32;

   --  Digest and block buffers exposed as subtypes for the rest of the stack.
   subtype Sha_Digest_Type is Sha_Digest_Array;
   subtype Sha_Block_Buffer is Sha_Block_Buffer_Array;

   procedure Compute_Sha_Digest
     (Buffer  : in     Interfaces.Unsigned_64;
      Digest  :    out Sha_Digest_Array;
      Success :    out Boolean)
   with
     Global => null,
     Post   => (if Success then Digest (1) /= 0 or Digest (8) /= 0);

end Schild_Sha_Manager;
