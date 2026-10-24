pragma Spark_Mode (On);

package body Schild_Star_Syscall_Loader is

   procedure Pack_Star_Register
     (Kernel_Target_CS : in     Segment_Selector;
      User_Target_CS   : in     Segment_Selector;
      Star_Value       :    out Star_Register_64)
   is
      Result : Star_Register_64;
   begin
      --  STAR holds the kernel/user CS selectors in bits 32/48.
      Result := Star_Register_64(Kernel_Target_CS) * 2**32;
      
      --  Pack the user selector into the high bits.
      Result := Result + (Star_Register_64(User_Target_CS) * 2**48);
      
      Star_Value := Result;
   end Pack_Star_Register;

end Schild_Star_Syscall_Loader;
