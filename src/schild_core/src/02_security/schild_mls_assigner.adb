package body Schild_Mls_Assigner with
  SPARK_Mode => On
is

   procedure Assign_Security_Level
     (Current_Level : in     Clear_Level_Type;
      New_Level     : in     Clear_Level_Type;
      Final_Level   :    out Clear_Level_Type;
      Success       :    out Boolean)
   is
   begin
      --  Accept the new level only when it does not lower clearance.
      if New_Level >= Current_Level then
         Final_Level := New_Level;
         Success     := True;
      else
         Final_Level := Current_Level;
         Success     := False;
      end if;
   end Assign_Security_Level;

end Schild_Mls_Assigner;
