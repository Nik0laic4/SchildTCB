with System.Machine_Code;

package body Schild_Fpu_State_Guard with SPARK_Mode => On is

   ---------------------------
   -- Sanitize_And_Save_Fpu --
   ---------------------------
   procedure Sanitize_And_Save_Fpu
     (State      : out Fpu_Guard_Record;
      Caller_PID : Interfaces.Unsigned_32) is
   begin
      --  Start from a zeroed, unsaved state.
      State := (Buffer => (others => 0), Owner_PID => Caller_PID, Is_Saved => False);

      --  Fence/save the FPU state.
      System.Machine_Code.Asm
        (Template => "finit\n\t" &
                     "dbswait",
         Volatile => True);

      State.Is_Saved := True;
   end Sanitize_And_Save_Fpu;

end Schild_Fpu_State_Guard;
