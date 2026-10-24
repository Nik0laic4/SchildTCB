with Interfaces; use Interfaces;

package Schild_Mls_Core_Engine with
  SPARK_Mode => On
is

   pragma Elaborate_Body;

    subtype Clear_Level_Type is Interfaces.Unsigned_32 range 1 .. 4;
   -- 1 = Public, 2 = Restricted, 3 = Confidential, 4 = Secret
   --
   -- NOTE (intentional level-model divergence): the standalone kernel uses this
   -- 4-level *commercial* scheme. The seL4 root task uses a 5-level *military*
   -- scheme -- Schild_Config_Daemon.Security_Level = (Public, Internal,
   -- Confidential, Secret, Top_Secret). They run in separate images and never
   -- share a runtime boundary; level 2 here is "Restricted" (not "Internal")
   -- and this model has no "Top_Secret".

   type Subject_Context_Record is record
      Subject_Id    : Interfaces.Unsigned_32 := 0;
      Clearance     : Clear_Level_Type := 1;
      Active_Rights : Interfaces.Unsigned_8 := 0;
   end record;

   procedure Evaluate_Read_Permission
     (Sub_Level : in     Clear_Level_Type;
      Obj_Level : in     Clear_Level_Type;
      Permitted :    out Boolean)
   with Post => (if Permitted then Sub_Level >= Obj_Level); --  No read up.

end Schild_Mls_Core_Engine;
