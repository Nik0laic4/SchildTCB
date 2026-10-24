pragma Spark_Mode (On);

with Interfaces;
use Interfaces; --  Unsigned_8 for the DRBG state.

package Schild_Ctr_Drbg_Engine is

   type Drbg_Vector_Array is array (0 .. 15) of Unsigned_8;

   procedure Reseed_Counter_State
     (State_V : in out Drbg_Vector_Array;
      Success :    out Boolean)
   with
     Global => null,
     Post   => (if Success then State_V (15) = State_V'Old (15) + 1);

end Schild_Ctr_Drbg_Engine;
