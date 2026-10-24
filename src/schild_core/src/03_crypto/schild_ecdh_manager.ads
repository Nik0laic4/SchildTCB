with Interfaces; use Interfaces;
with Schild_Ecc_Validator; use Schild_Ecc_Validator;

package Schild_Ecdh_Manager with
  SPARK_Mode => On
is

   type Key_Component_Type is new Interfaces.Unsigned_32;
   type Secret_Key_Array is array (1 .. 8) of Key_Component_Type;

   procedure Derive_Shared_Secret
     (Private_Key : in     Secret_Key_Array;
      Peer_Public : in     Secret_Key_Array;
      Secret      : in out Secret_Key_Array;
      Success     :    out Boolean)
   with
     Pre  => (for all I in Private_Key'Range => Private_Key(I) /= 0),
     Post => (if Success then (for some I in Secret'Range => Secret(I) /= 0));

end Schild_Ecdh_Manager;
