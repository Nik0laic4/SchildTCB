package body Schild_Crypto_Fabric with
  SPARK_Mode => On --  Session state machine; cipher cores are Schild_Aes_Ni_Core / Schild_HMAC_SHA256.
is

   procedure Initialize_Fabric_session
     (Control : in out Fabric_Control_Record;
      Success :    out Boolean)
   is
   begin
      --  Arm the session: mark the key ready and unlock the CBC context.
      Control.State := Key_Ready;
      Control.Cbc_Context.Is_Ready := True;
      Success := True;
   end Initialize_Fabric_session;

   procedure Process_Secure_Block
     (Control    : in out Fabric_Control_Record;
      Input_Data : in     Schild_Aes_Cbc_Engine.Cbc_Block_Buffer;
      Output_Data:    out Schild_Aes_Cbc_Engine.Cbc_Block_Buffer;
      Success    :    out Boolean)
   is
   begin
      --  Dispatch one secure block through the AES-CBC engine.
      Schild_Aes_Cbc_Engine.Encrypt_Cbc_Block
        (Context    => Control.Cbc_Context,
         Plaintext  => Input_Data,
         Ciphertext => Output_Data,
         Success    => Success);

      if Success then
         Control.State := Context_Active;
      else
         Control.State := Faulted;
      end if;
   end Process_Secure_Block;

end Schild_Crypto_Fabric;
