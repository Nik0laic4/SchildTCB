package body Schild_User_Vfs with
  SPARK_Mode => Off --  Sandbox path check: rejects ".." traversal.
is

   procedure Validate_Vfs_Sandbox_Path
     (Path   : in     Virtual_Path_String;
      Status :    out Vfs_Status_Type)
   is
   begin
      --  Default to granted; scan for a "../" traversal sequence.
      Status := Vfs_Access_Granted;
      for I in 1 .. Path.Length - 2 loop
         if Path.Data(I) = '.' and Path.Data(I+1) = '.' and Path.Data(I+2) = '/' then
            Status := Vfs_Path_Traversal_Detected;
         end if;
      end loop;
   end Validate_Vfs_Sandbox_Path;

end Schild_User_Vfs;
