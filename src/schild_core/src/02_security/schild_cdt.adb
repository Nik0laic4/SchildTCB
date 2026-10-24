package body Schild_CDT with SPARK_Mode is

   procedure Revoke_Capability
     (Manager : in out CDT_Manager;
      Parent  :        Valid_Cap_Id;
      Child   :        Valid_Cap_Id) is
   begin
      --  Empty the child first.
      Manager.Nodes (Child).Status    := Cap_Empty;
      Manager.Nodes (Child).Parent_Id := 0;

      --  Then empty the parent.
      Manager.Nodes (Parent).Status := Cap_Empty;
   end Revoke_Capability;

end Schild_CDT;
