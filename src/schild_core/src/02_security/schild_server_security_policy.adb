package body Schild_Server_Security_Policy with
  SPARK_Mode => On
is
   function Can_Communicate
     (Source_Role, Target_Role : Server_Role) return Boolean is
   begin
      return Default_Policy (Source_Role) = Default_Policy (Target_Role);
   end Can_Communicate;

   function Can_Read
     (Reader_Role, Owner_Role : Server_Role) return Boolean is
   begin
      return Default_Policy (Reader_Role) >= Default_Policy (Owner_Role);
   end Can_Read;

   function Can_Write
     (Writer_Role, Target_Role : Server_Role) return Boolean is
   begin
      return Default_Policy (Writer_Role) <= Default_Policy (Target_Role);
   end Can_Write;

end Schild_Server_Security_Policy;
