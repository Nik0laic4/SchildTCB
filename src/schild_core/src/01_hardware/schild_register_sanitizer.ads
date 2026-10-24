pragma Spark_Mode (On);

with Interfaces;
use Interfaces;

package Schild_Register_Sanitizer is

   type Register_Index_Range is range 0 .. 15;
   type Cpu_Context_Array is array (Register_Index_Range) of Unsigned_64;

   procedure Sanitize_Context
     (Context_Regs : out Cpu_Context_Array)
   with
     Global => null,
     Post   => (for all I in Register_Index_Range => Context_Regs(I) = 0);

end Schild_Register_Sanitizer;
