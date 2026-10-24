pragma Spark_Mode (On);

package body Schild_Simd_Sanitizer is

   procedure Sanitize_Simd_Registers
     (Regs         : in     Simd_Context_Array;
      Is_Sanitized :    out Boolean)
   is
      Current_Status : Boolean := True;
   begin
      for I in Register_ID loop
         if Regs(I) /= 0 then
            Current_Status := False;
         end if;
         pragma Loop_Invariant (Current_Status = (for all J in Register_ID'First .. I => Regs(J) = 0));
      end loop;

      Is_Sanitized := Current_Status;
   end Sanitize_Simd_Registers;

end Schild_Simd_Sanitizer;
