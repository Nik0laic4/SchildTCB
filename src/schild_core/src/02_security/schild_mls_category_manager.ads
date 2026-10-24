with Interfaces; use Interfaces;
with Schild_Mls_Core_Engine; use Schild_Mls_Core_Engine;

package Schild_Mls_Category_Manager with
  SPARK_Mode => On
is

   pragma Elaborate_Body;

   type Category_Mask_Type is new Interfaces.Unsigned_64;

   procedure Verify_Category_Compartment
     (Sub_Mask  : in     Category_Mask_Type;
      Obj_Mask  : in     Category_Mask_Type;
      Is_Subset :    out Boolean)
   with Post => (if Is_Subset then (Sub_Mask and Obj_Mask) = Obj_Mask); --  Need-to-know subset.

end Schild_Mls_Category_Manager;
