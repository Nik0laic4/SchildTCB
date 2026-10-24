package body Schild_Mount_Manager with
  SPARK_Mode => On --  Mount-point manager scaffold.
is

   procedure Register_Secure_Mount
     (Point      : in out Mount_Point_Record;
      Target_Ctx : in     Schild_User_Space.Context_Id_Type;
      Success    :    out Boolean)
   is
   begin
      --  Bind the mount point to the target context.
      Point.Context_Id := Target_Ctx;
      Point.Is_Mounted := True;
      Success          := True;
   end Register_Secure_Mount;

end Schild_Mount_Manager;
