pragma Spark_Mode (On);

package Schild_Simd_Sanitizer is

   type Register_ID is range 1 .. 16;
   type Vector_Value_64 is mod 2**64;
   type Simd_Context_Array is array (Register_ID) of Vector_Value_64;

   --  Clear SIMD state before returning to user space.
   procedure Sanitize_Simd_Registers
     (Regs         : in     Simd_Context_Array;
      Is_Sanitized :    out Boolean)
   with
     Global  => null,
     Depends => (Is_Sanitized => Regs),
     Post    => Is_Sanitized = (for all I in Register_ID => Regs(I) = 0);

end Schild_Simd_Sanitizer;
