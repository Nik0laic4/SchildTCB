with Interfaces; use Interfaces;
with Schild_Mls_Core_Engine; use Schild_Mls_Core_Engine;

package Schild_Mls_Assigner with
  SPARK_Mode => On
is
   pragma Elaborate_Body;

   procedure Assign_Security_Level
     (Current_Level : in     Clear_Level_Type;
      New_Level     : in     Clear_Level_Type;
      Final_Level   :    out Clear_Level_Type;
      Success       :    out Boolean)
   with Post => (if Success then
                   Final_Level = New_Level and Final_Level >= Current_Level
                 else
                   Final_Level = Current_Level and New_Level < Current_Level);
   --  Success: the requested level is accepted (never a downgrade).
   --  Failure: the request would lower clearance, so the level is unchanged.

end Schild_Mls_Assigner;
