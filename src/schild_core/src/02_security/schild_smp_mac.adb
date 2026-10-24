package body Schild_Smp_Mac with
  SPARK_Mode => Off --  BLP MAC: source must dominate target.
is

   procedure Enforce_Mac_Policy
     (Context : in out Mac_Context_Record)
   is
   begin
      --  Allow only when the source label dominates the target.
      if Context.Source_Label >= Context.Target_Label then
         Context.Access_Ok := True;
      else
         Context.Access_Ok := False;
      end if;
   end Enforce_Mac_Policy;

end Schild_Smp_Mac;
