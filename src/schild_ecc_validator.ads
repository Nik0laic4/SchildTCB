with Interfaces;

package Schild_Ecc_Validator with
  SPARK_Mode => On
is

   --  A 256-bit ECC key or hash (four 64-bit words).
   type Ecc_Key_Buffer is array (1 .. 4) of Interfaces.Unsigned_64;

   --  An ECDSA-style signature (R/S points).
   type Ecc_Signature_Type is record
      R_Point : Ecc_Key_Buffer;
      S_Value : Ecc_Key_Buffer;
   end record;

   --  Verify an ECC signature against the public key.
   procedure Verify_Ecc_Signature
     (Public_Key : in Ecc_Key_Buffer;
      Signature  : in Ecc_Signature_Type;
      Msg_Hash   : in Ecc_Key_Buffer;
      Is_Valid   : out Boolean)
   with
     --  A valid signature yields a non-zero message hash.
     Post => (if Is_Valid then Msg_Hash (1) /= 0 or Msg_Hash (2) /= 0);

end Schild_Ecc_Validator;
