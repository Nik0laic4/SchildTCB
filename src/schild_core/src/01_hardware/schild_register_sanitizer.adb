pragma Spark_Mode (On);

package body Schild_Register_Sanitizer is

   procedure Sanitize_Context
     (Context_Regs : out Cpu_Context_Array)
   is
   begin
      Context_Regs := (others => 0);
   end Sanitize_Context;

end Schild_Register_Sanitizer;
