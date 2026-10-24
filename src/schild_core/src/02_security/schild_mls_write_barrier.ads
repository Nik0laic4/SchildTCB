pragma Spark_Mode (On);

package Schild_Mls_Write_Barrier is

   type Security_Label_Type is range 0 .. 15;

   procedure Verify_Write_Permission
     (Subject_Label : in     Security_Label_Type;
      Object_Label  : in     Security_Label_Type;
      Is_Allowed    :    out Boolean)
   with
     Global => null,
     Post   => Is_Allowed = (Subject_Label <= Object_Label);

end Schild_Mls_Write_Barrier;
