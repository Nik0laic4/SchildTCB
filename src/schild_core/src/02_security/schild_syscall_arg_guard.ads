pragma Spark_Mode (On);

package Schild_Syscall_Arg_Guard is

   type Memory_Address is mod 2**64;

   --  Top of the user address space (47-bit canonical).
   USER_SPACE_MAX_ADDR : constant Memory_Address := 16#0000_7FFF_FFFF_FFFF#;

   --  A pointer is trusted when it fits inside user space (no overflow).
   procedure Validate_Syscall_Pointer
     (Arg_Pointer : in     Memory_Address;
      Arg_Length  : in     Memory_Address;
      Is_Trusted  :    out Boolean)
   with
     Global  => null,
     Depends => (Is_Trusted => (Arg_Pointer, Arg_Length)),
     Post    => (if Is_Trusted then 
                   Arg_Pointer <= USER_SPACE_MAX_ADDR and 
                   Arg_Length <= USER_SPACE_MAX_ADDR and
                   (USER_SPACE_MAX_ADDR - Arg_Pointer) >= Arg_Length
                 else 
                   Arg_Pointer > USER_SPACE_MAX_ADDR or 
                   Arg_Length > USER_SPACE_MAX_ADDR or
                   (USER_SPACE_MAX_ADDR - Arg_Pointer) < Arg_Length);

end Schild_Syscall_Arg_Guard;
