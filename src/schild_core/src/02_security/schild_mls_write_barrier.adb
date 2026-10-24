pragma Spark_Mode (On);

package body Schild_Mls_Write_Barrier is

   procedure Verify_Write_Permission
     (Subject_Label : in     Security_Label_Type;
      Object_Label  : in     Security_Label_Type;
      Is_Allowed    :    out Boolean)
   is
   begin
      --  No write down: the subject must not dominate the object.
      Is_Allowed := (Subject_Label <= Object_Label);
   end Verify_Write_Permission;

end Schild_Mls_Write_Barrier;
