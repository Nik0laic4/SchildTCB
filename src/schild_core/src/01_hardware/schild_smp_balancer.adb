package body Schild_Smp_Balancer with
  SPARK_Mode => On --  Task migration scaffold.
is

   procedure Balance_Cluster_Load
     (Source_Core : in     Core_Index_Type;
      Target_Core : in     Core_Index_Type;
      Success     :    out Boolean)
   is
      pragma Unreferenced (Source_Core, Target_Core);
   begin
      --  Not implemented: real load balancing requires the scheduler run-queues.
      --  Report honestly instead of claiming a successful migration.
      Success := False;
   end Balance_Cluster_Load;

end Schild_Smp_Balancer;
