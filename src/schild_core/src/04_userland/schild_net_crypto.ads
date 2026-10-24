with Interfaces; use Interfaces;

package Schild_Net_Crypto with
  SPARK_Mode => On
is

   type Crypto_Payload_Length is new Interfaces.Unsigned_32 range 0 .. 1480; --  Max MTU-sized payload.

   type Network_Session_Record is record
      Session_Id   : Interfaces.Unsigned_64 := 0;
      Is_Encrypted : Boolean := False;
   end record;

   procedure Encrypt_Network_Buffer
     (Session     : in out Network_Session_Record;
      Payload_Len : in     Crypto_Payload_Length;
      Success     :    out Boolean)
   with Pre => Session.Session_Id /= 0,
        Post => (if Success then Session.Is_Encrypted);

end Schild_Net_Crypto;
