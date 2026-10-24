with System.Machine_Code;

package body Schild_Debug_Context_Switcher with SPARK_Mode => On is

   ------------------------------------
   -- Switch_And_Clear_Debug_Context --
   ------------------------------------
   procedure Switch_And_Clear_Debug_Context
     (Old_Context : out Debug_Context_Record;
      New_PID     : Interfaces.Unsigned_32) is
   begin
      --  Start from a cleared debug context.
      Old_Context := (DR0_Val   => 0, 
                      DR1_Val   => 0, 
                      DR7_Ctrl  => 16#0400#, 
                      Owner_PID => New_PID, 
                      Is_Clean  => False);

      --  Load/clear the debug registers via inline assembly.
      System.Machine_Code.Asm
        (Template => "movq %0, %%dr0\n\t" &
                     "movq %0, %%dr1\n\t" &
                     "movq %1, %%dr7",
         Inputs   => (Interfaces.Unsigned_64'Input ("r", Interfaces.Unsigned_64'(0)),
                      Interfaces.Unsigned_64'Input ("r", Interfaces.Unsigned_64'(16#0400#))),
         Volatile => True);

      Old_Context.Is_Clean := True;
   end Switch_And_Clear_Debug_Context;

end Schild_Debug_Context_Switcher;
