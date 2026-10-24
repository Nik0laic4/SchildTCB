pragma Spark_Mode (On);

with Interfaces;
use Interfaces;

package body Schild_Ctr_Drbg_Engine is

   procedure Reseed_Counter_State
     (State_V : in out Drbg_Vector_Array;
      Success :    out Boolean)
   is
   begin
      --  Increment the counter without overflow.
      if State_V (15) < Unsigned_8'Last then
         State_V (15) := State_V (15) + 1;
         Success      := True;
      else
         Success      := False;
      end if;
   end Reseed_Counter_State;

end Schild_Ctr_Drbg_Engine;
