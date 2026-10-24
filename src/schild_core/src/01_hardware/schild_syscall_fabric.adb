with Schild_Syscall_Arg_Guard; use Schild_Syscall_Arg_Guard;

package body Schild_Syscall_Fabric with
  SPARK_Mode => On --  Orchestrates syscall entry gates.
is

   EACCES : constant Interfaces.Unsigned_64 := 16#0D#;
   --  POSIX "Permission denied" (errno 13): the access-denied return code
   --  mirrored into RAX when the argument guard rejects the syscall.

   procedure Dispatch_User_Syscall
     (Context : in out Syscall_Context_Record;
      Success :    out Boolean)
   is
      Pointer_Trusted : Boolean;
   begin
      --  Enforce the argument guard before any dispatch: the user-supplied
      --  buffer must lie entirely inside canonical user space.
      Validate_Syscall_Pointer
        (Arg_Pointer => Context.Arg_Pointer,
         Arg_Length  => Context.Arg_Length,
         Is_Trusted  => Pointer_Trusted);

      if not Pointer_Trusted then
         --  Guard violation: deny with EACCES in the RAX mirror.
         Context.Return_Value := EACCES;
         Context.Is_Processed := False;
         Success := False;
         return;
      end if;

      --  Mark the captured arguments as validated.
      Context.Args_Valid := True;

      --  SIMD context cleanup (simulated call schild_simd_sanitizer).
      Context.Simd_Clean := True;

      if Context.Args_Valid and Context.Simd_Clean then
         Context.Return_Value := 0;
         Context.Is_Processed := True;
         Success := True;
      else
         Success := False;
      end if;
   end Dispatch_User_Syscall;

end Schild_Syscall_Fabric;
