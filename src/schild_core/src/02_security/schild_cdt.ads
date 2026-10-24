package Schild_CDT with SPARK_Mode is

   Max_Caps : constant := 10;
   type Cap_Id is range 0 .. Max_Caps; --  0 denotes "no parent" / empty.
   subtype Valid_Cap_Id is Cap_Id range 1 .. Max_Caps;

   type Cap_Status is (Cap_Empty, Cap_Active);

   --  A node of the capability derivation tree.
   type CDT_Node is record
      Status    : Cap_Status := Cap_Empty;
      Parent_Id : Cap_Id     := 0; --  Parent capability in the tree (0 = root).
   end record;

   type CDT_Table_Type is array (Valid_Cap_Id) of CDT_Node;

   type CDT_Manager is record
      Nodes : CDT_Table_Type := (others => (Status => Cap_Empty, Parent_Id => 0));
   end record;

   --  Revoke a child capability and its parent in one step.
   --  The derivation tree guarantees the child was minted from the parent.
   procedure Revoke_Capability
     (Manager : in out CDT_Manager;
      Parent  :        Valid_Cap_Id;
      Child   :        Valid_Cap_Id)
   with
     Pre  => Parent /= Child and then
             Manager.Nodes (Child).Parent_Id = Cap_Id (Parent),
     Post => Manager.Nodes (Parent).Status = Cap_Empty and then
             Manager.Nodes (Child).Status = Cap_Empty;

end Schild_CDT;
