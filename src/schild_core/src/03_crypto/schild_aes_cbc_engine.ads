with Interfaces; use Interfaces;

package Schild_Aes_Cbc_Engine with
  SPARK_Mode => On
is

   type Cbc_Block_Buffer is array (1 .. 16) of Interfaces.Unsigned_8;
   
   --  The IV shares the 16-byte shape of a CBC data block.
   subtype Iv_Buffer_Type is Cbc_Block_Buffer;

   type Crypto_Context_Record is record
      Initialization_Vector : Iv_Buffer_Type := (others => 0);
      Is_Ready              : Boolean := False;
   end record;

   procedure Encrypt_Cbc_Block
     (Context   : in out Crypto_Context_Record;
      Plaintext : in     Cbc_Block_Buffer;
      Ciphertext:    out Cbc_Block_Buffer;
      Success   :    out Boolean)
   with Pre => Context.Is_Ready,
        Post => (if Success then
                   --  CBC chaining (FIPS 800-38A): the ciphertext block is the
                   --  plaintext XOR the running IV, and the IV advances to the
                   --  new ciphertext. Together these rule out both ECB-style
                   --  block replay and un-whitened leakage (threat model A1).
                   Context.Initialization_Vector = Ciphertext
                   and (for all I in Cbc_Block_Buffer'Range =>
                          Ciphertext (I) = (Plaintext (I) xor Context'Old.Initialization_Vector (I))));

end Schild_Aes_Cbc_Engine;
