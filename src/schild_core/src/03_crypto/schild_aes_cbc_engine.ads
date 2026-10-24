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
        Post => (if Success then Context.Initialization_Vector = Ciphertext);

end Schild_Aes_Cbc_Engine;
