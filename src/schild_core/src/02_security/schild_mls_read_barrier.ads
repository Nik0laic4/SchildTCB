with Interfaces;
with Schild_Mls_Core_Engine; use Schild_Mls_Core_Engine;
use type Interfaces.Unsigned_32;

package Schild_Mls_Read_Barrier with
  SPARK_Mode => On
is
   pragma Elaborate_Body;

   procedure Enforce_Read_Policy
     (Subject_Level : in     Clear_Level_Type;
      Object_Level  : in     Clear_Level_Type;
      Allow_Read    :    out Boolean)
   with Post => (if Allow_Read then Subject_Level >= Object_Level);

end Schild_Mls_Read_Barrier;
