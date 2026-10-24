package body Schild_Stack_Backtrace with
  SPARK_Mode => Off --  RBP chain walk (scaffold).
is

   procedure Capture_Kernel_Backtrace
     (Stack_Base  : in     Long_Integer;
      Stack_Limit : in     Long_Integer;
      Current_RBP : in     Long_Integer;
      Trace       :    out Backtrace_Storage_Type;
      Frames_Read :    out Natural)
   is
   begin
      --  Start with a clean trace.
      Trace       := (others => 0);
      Frames_Read := 0;
   end Capture_Kernel_Backtrace;

end Schild_Stack_Backtrace;
