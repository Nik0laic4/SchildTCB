with Interfaces; use Interfaces;

package Schild_Rsa_Manager with
  SPARK_Mode => On
is

   type Rsa_Block_Array is array (1 .. 64) of Interfaces.Unsigned_32;

   procedure Encrypt_Rsa_Black
     (Message : in     Rsa_Block_Array;
      Key_E   : in     Interfaces.Unsigned_32;
      Mod_N   : in     Rsa_Block_Array;
      Result  : in out Rsa_Block_Array);

end Schild_Rsa_Manager;
