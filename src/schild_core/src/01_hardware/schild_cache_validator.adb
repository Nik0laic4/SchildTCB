with System.Machine_Code; use System.Machine_Code;

package body Schild_Cache_Validator with
  SPARK_Mode => Off
is

   ----------------------------
   -- Validate_Core_Topology --
   ----------------------------
   procedure Validate_Core_Topology
     (Cluster  : in CPU_Cluster_Id;
      Index    : in Natural;
      Topology : out Core_Topology_Type)
   is
   begin
      -- 1. Primary initialization topology passport kernel
      Topology.Cluster_ID     := Cluster;
      Topology.Core_Index     := Index;
      Topology.Is_Coherent    := False;
      Topology.Barrier_Active := False;

      -- 2. Forced hardware barrier call memory sfence (Store Fence)
      --  sfence orders stores before the topology probe.
      Asm (Template => "sfence", Volatile => True);
      Topology.Barrier_Active := True;

      --  Only the first 16 indices are valid.
      if Index < 16 then
         Topology.Is_Coherent := True;
      end if;

      --  Final sfence after the probe.
      Asm (Template => "sfence", Volatile => True);
   end Validate_Core_Topology;

end Schild_Cache_Validator;
