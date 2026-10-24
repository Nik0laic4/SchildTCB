package body Schild_User_Irq with
  SPARK_Mode => Off --  Scaffold: binds a user IRQ vector to a process.
is

   procedure Bind_User_Vector
     (Vector     : in     User_Irq_Vector;
      Target_PID : in     Interfaces.Unsigned_32;
      Descriptor :    out Irq_Descriptor_Record;
      Success    :    out Boolean)
   is
   begin
      --  Record the owner and mark the vector bound.
      Descriptor.Owner_PID := Target_PID;
      Descriptor.Is_Bound  := True;
      Success              := True;
   end Bind_User_Vector;

end Schild_User_Irq;
