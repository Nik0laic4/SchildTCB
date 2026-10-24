with Interfaces; use Interfaces;
with Schild_Smp_Spinlock;
with Schild_Ipi_Vector_Guard;

package Schild_Smp_Ipi_Queue with
  SPARK_Mode => On
is
   pragma Elaborate_Body;

   type Ipi_Message_Record is record
      Target_Core : Schild_Smp_Spinlock.Core_Id_Type := 0;
      Vector      : Schild_Ipi_Vector_Guard.Ipi_Vector_Type := 240;
      Pending     : Boolean := False;
   end record;

   procedure Enqueue_Ipi_Request
     (Message : in out Ipi_Message_Record;
      Success :    out Boolean)
   with Post => (if Success then Message.Pending);

end Schild_Smp_Ipi_Queue;
