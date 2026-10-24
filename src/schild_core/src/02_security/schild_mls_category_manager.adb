package body Schild_Mls_Category_Manager with
  SPARK_Mode => On --  Compartment subset check (need-to-know).
is

   procedure Verify_Category_Compartment
     (Sub_Mask  : in     Category_Mask_Type;
      Obj_Mask  : in     Category_Mask_Type;
      Is_Subset :    out Boolean)
   is
   begin
      --  The subject may access the object when its categories contain it.
      if (Sub_Mask and Obj_Mask) = Obj_Mask then
         Is_Subset := True;
      else
         Is_Subset := False;
      end if;
   end Verify_Category_Compartment;

end Schild_Mls_Category_Manager;
