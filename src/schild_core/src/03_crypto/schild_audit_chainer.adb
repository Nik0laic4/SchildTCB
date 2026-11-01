package body Schild_Audit_Chainer with
  SPARK_Mode => On
is

   procedure Link_Audit_Record
     (Previous_Hash : in     Hash_Digest_Type;
      Record_Payload : in     Hash_Digest_Type;
      Current_Hash  : in out Hash_Digest_Type;
      Passport      :    out Blockchain_Passport_Record;
      Success       :    out Boolean)
   is
      Hash_Valid : Boolean := True;
   begin
      --  Chain the record: fold the payload over the previous link (XOR).
      for I in Current_Hash'Range loop
         Current_Hash(I) := Previous_Hash(I) xor Record_Payload(I);

         --  Each already-written word equals the XOR of its predecessor word
         --  and its payload word; at loop exit this covers the whole digest.
         pragma Loop_Invariant
           (for all J in Current_Hash'First .. I =>
              Current_Hash (J) = (Previous_Hash (J) xor Record_Payload (J)));
      end loop;

      Passport.Block_Sequence_Id := 1;
      Passport.Is_Chain_Valid    := Hash_Valid;
      Success                    := Hash_Valid;
   end Link_Audit_Record;

end Schild_Audit_Chainer;
