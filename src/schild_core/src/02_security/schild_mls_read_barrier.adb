package body Schild_Mls_Read_Barrier with
  SPARK_Mode => On
is
   procedure Enforce_Read_Policy
     (Subject_Level : in     Clear_Level_Type;
      Object_Level  : in     Clear_Level_Type;
      Allow_Read    :    out Boolean)
   is
   begin
      --  Delegate to the read-permission evaluator.
      Evaluate_Read_Permission (Subject_Level, Object_Level, Allow_Read);
   end Enforce_Read_Policy;
end Schild_Mls_Read_Barrier;
