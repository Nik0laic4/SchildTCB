package body Schild_Trap_Handler with
  SPARK_Mode => Off --  Trap dispatch scaffold.
is

   procedure Dispatch_Hardware_Trap
     (Context  : in     Trap_Context_Record;
      Response :    out Trap_Response_Type)
   is
   begin
      if Context.Vector_Num = 14 then
         Response := Trap_Kernel_Panic;
      else
         Response := Trap_Handled;
      end if;
   end Dispatch_Hardware_Trap;

end Schild_Trap_Handler;
