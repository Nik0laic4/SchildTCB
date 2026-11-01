-- Schild TCB — audit-chain link (tamper-evidence scaffold).
--
-- NOTE (2026-11-01): NOT wired into the live audit path (Schild_Audit_Logger
-- persists events but does not chain them yet). The XOR fold below is a
-- placeholder for a cryptographic hash — the real SHA-256 compression lives in
-- Schild_HMAC_SHA256 (body Off, KAT-validated). What the contract proves is the
-- *chaining dependency*: every link depends on its predecessor and its payload,
-- so tampering with any record changes every subsequent link.

with Interfaces; use Interfaces;

package Schild_Audit_Chainer with
  SPARK_Mode => On
is

   --  One 32-bit word of a hash digest; a digest is eight such words.
   type Hash_Word_Type is new Interfaces.Unsigned_32;
   type Hash_Digest_Type is array (1 .. 8) of Hash_Word_Type;

   type Blockchain_Passport_Record is record
      Block_Sequence_Id : Interfaces.Unsigned_64 := 0;
      Is_Chain_Valid    : Boolean := False;
   end record;

   procedure Link_Audit_Record
     (Previous_Hash : in     Hash_Digest_Type;
      Record_Payload : in     Hash_Digest_Type;
      Current_Hash  : in out Hash_Digest_Type;
      Passport      :    out Blockchain_Passport_Record;
      Success       :    out Boolean)
   with
     --  Tamper-evidence (threat model A4): the new link is a deterministic
     --  function of the previous link and the payload. Modifying any record
     --  (or its predecessor) therefore changes every subsequent link.
     Post => Success
             and Passport.Is_Chain_Valid
             and Passport.Block_Sequence_Id = 1
             and (for all I in Current_Hash'Range =>
                    Current_Hash (I) = (Previous_Hash (I) xor Record_Payload (I)));

end Schild_Audit_Chainer;
