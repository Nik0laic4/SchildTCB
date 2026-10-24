package body Schild_Mls_Core_Engine with
  SPARK_Mode => On --  Core BLP read/write decision engine.
is

   procedure Evaluate_Read_Permission
     (Sub_Level : in     Clear_Level_Type;
      Obj_Level : in     Clear_Level_Type;
      Permitted :    out Boolean)
   is
   begin
      if Sub_Level >= Obj_Level then
         Permitted := True;
      else
         Permitted := False;
      end if;
   end Evaluate_Read_Permission;

end Schild_Mls_Core_Engine;
