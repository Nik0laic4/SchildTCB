with Interfaces; use Interfaces;
with Schild_Sha_Manager; use Schild_Sha_Manager;

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
     Pre  => (for all I in Previous_Hash'Range => Previous_Hash(I) /= 0),
     Post => (if Success then Passport.Is_Chain_Valid and Passport.Block_Sequence_Id > 0);

end Schild_Audit_Chainer;
