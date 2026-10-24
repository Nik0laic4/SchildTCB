with Interfaces; use Interfaces;

package Schild_User_Irq with
  SPARK_Mode => On
is

   --  User IRQ vectors live in the 64..95 range.
   type User_Irq_Vector is new Interfaces.Unsigned_32 range 64 .. 95;

   type Irq_Descriptor_Record is record
      Owner_PID  : Interfaces.Unsigned_32 := 0;
      Is_Bound   : Boolean := False;
   end record;

   procedure Bind_User_Vector
     (Vector     : in     User_Irq_Vector;
      Target_PID : in     Interfaces.Unsigned_32;
      Descriptor :    out Irq_Descriptor_Record;
      Success    :    out Boolean)
   with Pre => Target_PID > 1,
        Post => (if Success then Descriptor.Is_Bound and Descriptor.Owner_PID = Target_PID);

end Schild_User_Irq;
