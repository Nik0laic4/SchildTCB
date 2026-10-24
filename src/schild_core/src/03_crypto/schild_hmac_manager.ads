pragma Spark_Mode (On);

with Interfaces;
use Interfaces; --  Unsigned_32 for the HMAC key-block words.

package Schild_Hmac_Manager is

   type Hmac_Block_Index_Type is range 1 .. 64;
   type Hmac_Key_Buffer is array (Hmac_Block_Index_Type) of Unsigned_32;

   procedure Compute_Hmac
     (Key     : in     Hmac_Key_Buffer;
      Success :    out Boolean)
   with
     Global => null;

end Schild_Hmac_Manager;
