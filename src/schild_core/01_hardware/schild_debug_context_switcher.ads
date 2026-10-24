with Interfaces;
use type Interfaces.Unsigned_64;
use type Interfaces.Unsigned_32;

package Schild_Debug_Context_Switcher with SPARK_Mode => On is

   type Debug_Context_Record is record
      DR0_Val   : Interfaces.Unsigned_64 := 0;
      DR1_Val   : Interfaces.Unsigned_64 := 0;
      DR7_Ctrl  : Interfaces.Unsigned_64 := 0;
      Owner_PID : Interfaces.Unsigned_32 := 0;
      Is_Clean  : Boolean := False;
   end record;

   --  Save and clear the hardware debug registers.
   procedure Switch_And_Clear_Debug_Context
     (Old_Context : out Debug_Context_Record;
      New_PID     : Interfaces.Unsigned_32)
   with
     Post => Old_Context.Is_Clean 
             and Old_Context.Owner_PID = New_PID
             and Old_Context.DR0_Val = 0
             and Old_Context.DR1_Val = 0
             and Old_Context.DR7_Ctrl = 16#0400#; --  DR7 must be in its default state.

end Schild_Debug_Context_Switcher;
