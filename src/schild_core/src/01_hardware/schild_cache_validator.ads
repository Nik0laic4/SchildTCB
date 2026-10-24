package Schild_Cache_Validator with
  SPARK_Mode => Off
is

   --  A CPU belongs to one of four clusters.
   type CPU_Cluster_Id is mod 4;

   --  Cache topology of a core.
   type Core_Topology_Type is record
      Cluster_ID      : CPU_Cluster_Id;
      Core_Index      : Natural;
      Is_Coherent     : Boolean;
      Barrier_Active  : Boolean;
   end record;

   --  Verify the topology is consistent.
   procedure Validate_Core_Topology
     (Cluster  : in CPU_Cluster_Id;
      Index    : in Natural;
      Topology : out Core_Topology_Type)
   with
     Post => Topology.Cluster_ID = Cluster 
             and Topology.Core_Index = Index 
             and Topology.Barrier_Active;

end Schild_Cache_Validator;
