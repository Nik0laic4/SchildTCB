with Interfaces; use Interfaces;
with Schild_Syscall_Arg_Guard; use Schild_Syscall_Arg_Guard;

package Schild_Syscall_Fabric with
  SPARK_Mode => On
is
   pragma Elaborate_Body;

   type Syscall_Id_Type is new Interfaces.Unsigned_32 range 0 .. 512;
   
   type Syscall_Context_Record is record
      Call_Id      : Syscall_Id_Type := 0;
      Arg_Pointer  : Memory_Address := 0;
      Arg_Length   : Memory_Address := 0;
      Args_Valid   : Boolean := False;
      Simd_Clean   : Boolean := False;
      Is_Processed : Boolean := False;
      Return_Value : Interfaces.Unsigned_64 := 0;  --  mirrors RAX on return
   end record;

   procedure Dispatch_User_Syscall
     (Context : in out Syscall_Context_Record;
      Success :    out Boolean)
   with Post => (if Success then
                   Context.Args_Valid and Context.Simd_Clean
                   and Context.Return_Value = 0);
   --  Success requires validated args, clean SIMD state and a zero return
   --  code; a guard violation denies with EACCES in Return_Value.

end Schild_Syscall_Fabric;
