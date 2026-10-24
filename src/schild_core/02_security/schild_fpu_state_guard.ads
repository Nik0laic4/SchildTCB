with Interfaces;
use type Interfaces.Unsigned_32;

package Schild_Fpu_State_Guard with SPARK_Mode => On is

   --  FPU state is 512 bytes.
   Fpu_State_Size : constant := 512;
   
   type Fpu_State_Buffer is array (1 .. Fpu_State_Size) of Interfaces.Unsigned_8;

   type Fpu_Guard_Record is record
      Buffer    : Fpu_State_Buffer := (others => 0);
      Owner_PID : Interfaces.Unsigned_32 := 0;
      Is_Saved  : Boolean := False;
   end record;

   --  Sanitize then save the FPU state.
   procedure Sanitize_And_Save_Fpu
     (State      : out Fpu_Guard_Record;
      Caller_PID : Interfaces.Unsigned_32)
   with
     Post => State.Is_Saved 
             and State.Owner_PID = Caller_PID
             and (for all I in State.Buffer'Range => State.Buffer(I) = 0);

end Schild_Fpu_State_Guard;
