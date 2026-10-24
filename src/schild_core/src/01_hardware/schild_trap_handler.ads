with Interfaces; use Interfaces;

package Schild_Trap_Handler with
  SPARK_Mode => On
is

   type Trap_Vector_Type is new Interfaces.Unsigned_32 range 0 .. 31;
   type Trap_Response_Type is (Trap_Handled, Trap_Forward_To_User, Trap_Kernel_Panic);

   type Trap_Context_Record is record
      Vector_Num : Trap_Vector_Type;
      Error_Code : Interfaces.Unsigned_64 := 0;
      Fault_Linear_Address : Interfaces.Unsigned_64 := 0; --  Faulting address (for #PF).
   end record;

   procedure Dispatch_Hardware_Trap
     (Context  : in     Trap_Context_Record;
      Response :    out Trap_Response_Type)
   with Post => (if Context.Vector_Num = 14 then Response = Trap_Kernel_Panic); --  A page fault (vector 14) always panics.

end Schild_Trap_Handler;
