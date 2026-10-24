with Interfaces;

package Schild_Aes_Ni_Core with
  SPARK_Mode => On
is

   --  A 16-byte AES block.
   subtype Aes_Block_Index is Natural range 0 .. 15;
   type Aes_Block_Type is array (Aes_Block_Index) of Interfaces.Unsigned_8 
     with Alignment => 16;

   --  Result of a hardware-accelerated AES round.
   type Aes_Ni_Passport is record
      Is_Hardware_Accelerated : Boolean;
      Is_Aligned              : Boolean;
      Is_Sealed               : Boolean;
   end record;

   --  Apply one AES-NI round to the state.
   procedure Encrypt_Single_Round
     (State    : in out Aes_Block_Type;
      Round_Key: in Aes_Block_Type;
      Passport : out Aes_Ni_Passport;
      Success  : out Boolean)
   with
     --  Both buffers must be 16-byte aligned for AES-NI.
     Pre  => State'Alignment >= 16 and Round_Key'Alignment >= 16,
     --  On success the passport reports a sealed, aligned round.
     Post => (if Success then 
                Passport.Is_Hardware_Accelerated 
                and Passport.Is_Aligned 
                and Passport.Is_Sealed);

end Schild_Aes_Ni_Core;
