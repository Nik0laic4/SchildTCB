with Interfaces; use Interfaces;
with Schild_User_Space; use Schild_User_Space;

package Schild_Mount_Manager with
  SPARK_Mode => On
is
   pragma Elaborate_Body;

   type Mount_Id_Type is new Interfaces.Unsigned_32 range 1 .. 1024;
   
   type Mount_Point_Record is record
      Id         : Mount_Id_Type := 1;
      Context_Id : Schild_User_Space.Context_Id_Type := 1;
      Is_Mounted : Boolean := False;
      Is_ReadOnly: Boolean := True;
   end record;

   procedure Register_Secure_Mount
     (Point      : in out Mount_Point_Record;
      Target_Ctx : in     Schild_User_Space.Context_Id_Type;
      Success    :    out Boolean)
   with Pre  => not Point.Is_Mounted,
        Post => (if Success then Point.Is_Mounted and Point.Context_Id = Target_Ctx);
   --  A successful mount binds the point to the target context.

end Schild_Mount_Manager;
