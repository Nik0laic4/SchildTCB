pragma Spark_Mode (On);

package body Schild_Route_Manager with SPARK_Mode => Off is

   procedure Lookup_Secure_Route
     (Target_IP   : in     Interfaces.Unsigned_32;
      Table       : in     Route_Table_Matrix;
      Route_Found :    out Boolean;
      Route_Idx   :    out Route_Id_Type)
   is
   begin
      Route_Found := False;
      Route_Idx   := Route_Id_Type'First;

      --  Iterate over all routes.
      for I in Route_Id_Type loop
         if Table(I).Is_Active and then Table(I).Gateway_IP = Target_IP then
            Route_Idx   := I;
            Route_Found := True;
         end if;
         pragma Loop_Invariant (I >= Route_Id_Type'First);
      end loop;
   end Lookup_Secure_Route;

end Schild_Route_Manager;
