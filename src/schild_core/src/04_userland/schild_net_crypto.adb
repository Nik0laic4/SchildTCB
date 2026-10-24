package body Schild_Net_Crypto with
  SPARK_Mode => Off --  Scaffold: marks the session buffer as encrypted.
is

   procedure Encrypt_Network_Buffer
     (Session     : in out Network_Session_Record;
      Payload_Len : in     Crypto_Payload_Length;
      Success     :    out Boolean)
   is
   begin
      --  Scaffold: no cipher is applied.
      Session.Is_Encrypted := True;
      Success              := True;
   end Encrypt_Network_Buffer;

end Schild_Net_Crypto;
