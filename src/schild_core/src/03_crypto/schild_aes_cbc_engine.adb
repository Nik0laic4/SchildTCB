package body Schild_Aes_Cbc_Engine with
  SPARK_Mode => Off --  CBC chaining over Schild_Aes_Ni_Core (block cipher is public; CBC wiring pending).
is

   procedure Encrypt_Cbc_Block
     (Context   : in out Crypto_Context_Record;
      Plaintext : in     Cbc_Block_Buffer;
      Ciphertext:    out Cbc_Block_Buffer;
      Success   :    out Boolean)
   is
      Xor_Block : Cbc_Block_Buffer;
   begin
      --  CBC chaining: XOR the plaintext block with the running IV.
      for I in 1 .. 16 loop
         Xor_Block(I) := Plaintext(I) xor Context.Initialization_Vector(I);
      end loop;

      --  Emit the ciphertext block.
      Ciphertext := Xor_Block;

      --  Advance the chaining state: the ciphertext becomes the next IV.
      Context.Initialization_Vector := Ciphertext;
      Success                       := True;
   end Encrypt_Cbc_Block;

end Schild_Aes_Cbc_Engine;
