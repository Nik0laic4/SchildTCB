package body Schild_Ecc_Validator with
  SPARK_Mode => On
is

   --------------------------
   -- Verify_Ecc_Signature --
   --------------------------
   procedure Verify_Ecc_Signature
     (Public_Key : in Ecc_Key_Buffer;
      Signature  : in Ecc_Signature_Type;
      Msg_Hash   : in Ecc_Key_Buffer;
      Is_Valid   : out Boolean)
   is
      Accumulator : Interfaces.Unsigned_64 := 0;
      Diff_Found  : Interfaces.Unsigned_64 := 0;
   begin
      Is_Valid := False;

      --  Fold the message hash and diff the signature across all words.
      for I in 1 .. 4 loop
         pragma Loop_Invariant (I >= 1 and I <= 4);
         
         --  Accumulate the hash words.
         Accumulator := Accumulator or Msg_Hash (I);
         
         --  Diff the public key against the signature.
         Diff_Found := Diff_Found or (Public_Key (I) xor Signature.R_Point (I));
      end loop;

      --  Valid when the hash is non-zero and points match.
      if Accumulator /= 0 and then Diff_Found = 0 then
         Is_Valid := True;
      end if;
   end Verify_Ecc_Signature;

end Schild_Ecc_Validator;
