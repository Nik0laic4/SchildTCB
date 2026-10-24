pragma Spark_Mode (On);

package Schild_Msr_Syscall_Core is

   type Msr_Register_64 is mod 2**64;

   --  Required FMASK (clear TF/IF/DF/IOPL on syscall).
   REQUIRED_FMASK : constant Msr_Register_64 := 16#0000_3E00#;

   --  A valid syscall MSR context needs LSTAR and the right FMASK.
   procedure Validate_Syscall_Msr_Context
     (Lstar_Address : in     Msr_Register_64;
      Fmask_Value   : in     Msr_Register_64;
      Is_Safe       :    out Boolean)
   with
     Global  => null,
     Depends => (Is_Safe => (Lstar_Address, Fmask_Value)),
     Post    => (if Is_Safe then 
                   Lstar_Address /= 0 and 
                   Fmask_Value = REQUIRED_FMASK
                 else 
                   Lstar_Address = 0 or 
                   Fmask_Value /= REQUIRED_FMASK);

end Schild_Msr_Syscall_Core;
