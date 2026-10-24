with System.Machine_Code; use System.Machine_Code;

package body Schild_Spec_Barrier with
  SPARK_Mode => Off --  LFENCE serialization: outside SPARK's model.
is

   procedure Enforce_Speculative_Barrier
     (Passport : out Barrier_Passport_Record;
      Success  : out Boolean)
   is
   begin
      --  LFENCE serializes the instruction stream and blocks speculative
      --  execution past the barrier (x86 Spectre V1/V2 mitigation).
      Asm (Template => "lfence", Volatile => True);
      Passport.Is_Fence_Active := True;
      Success                  := True;
   end Enforce_Speculative_Barrier;

end Schild_Spec_Barrier;
