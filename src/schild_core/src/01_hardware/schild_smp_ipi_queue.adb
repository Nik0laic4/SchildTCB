package body Schild_Smp_Ipi_Queue with
  SPARK_Mode => On
is
   procedure Enqueue_Ipi_Request
     (Message : in out Ipi_Message_Record;
      Success :    out Boolean)
   is
   begin
      --  Mark the IPI as pending.
      Message.Pending := True;
      Success := True;
   end Enqueue_Ipi_Request;
end Schild_Smp_Ipi_Queue;
