package Schild_Stack_Backtrace with
  SPARK_Mode => On
is

   --  A backtrace captures up to eight frames.
   subtype Trace_Depth_Range is Positive range 1 .. 8;
   type Backtrace_Storage_Type is array (Trace_Depth_Range) of Long_Integer;

   --  Walk the kernel stack and record return addresses.
   procedure Capture_Kernel_Backtrace
     (Stack_Base  : in Long_Integer;
      Stack_Limit : in Long_Integer;
      Current_RBP : in Long_Integer;
      Trace       : out Backtrace_Storage_Type;
      Frames_Read : out Natural)
   with
     --  The stack must be sane before walking it.
     Pre  => Stack_Base > Stack_Limit and Current_RBP /= 0,
     Post => Frames_Read <= 8;

end Schild_Stack_Backtrace;
