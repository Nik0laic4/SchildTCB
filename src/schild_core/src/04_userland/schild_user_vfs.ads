with Interfaces; use Interfaces;

package Schild_User_Vfs with
  SPARK_Mode => On
is

   --  A virtual path is a fixed 255-byte string plus its length.
   subtype Path_Length_Type is Positive range 1 .. 255;
   type Virtual_Path_String is record
      Length : Path_Length_Type := 1;
      Data   : String (1 .. 255) := (others => ' ');
   end record;

   type Vfs_Status_Type is (Vfs_Access_Granted, Vfs_Path_Traversal_Detected, Vfs_Invalid_Path);

   procedure Validate_Vfs_Sandbox_Path
     (Path   : in     Virtual_Path_String;
      Status :    out Vfs_Status_Type)
   with Pre => Path.Length > 0;

end Schild_User_Vfs;
