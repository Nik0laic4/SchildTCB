pragma Spark_Mode (On);

package Schild_Star_Syscall_Loader is

   type Segment_Selector is mod 2**16;
   type Star_Register_64 is mod 2**64;

   --  Pack kernel/user CS selectors into the STAR MSR value.
   procedure Pack_Star_Register
     (Kernel_Target_CS : in     Segment_Selector;
      User_Target_CS   : in     Segment_Selector;
      Star_Value       :    out Star_Register_64)
   with
     Global  => null,
     Depends => (Star_Value => (Kernel_Target_CS, User_Target_CS)),
     Post    => Star_Value = (Star_Register_64(Kernel_Target_CS) * 2**32) + 
                              (Star_Register_64(User_Target_CS) * 2**48);

end Schild_Star_Syscall_Loader;
