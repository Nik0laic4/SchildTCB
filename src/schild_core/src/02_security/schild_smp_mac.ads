with Interfaces; use Interfaces;
with Schild_Smp_Spinlock;

package Schild_Smp_Mac with
  SPARK_Mode => On
is

   type Security_Label_Type is new Interfaces.Unsigned_32 range 1 .. 4;
   -- 1 = Unclassified, 2 = Confidential, 3 = Secret, 4 = Top_Secret

   type Mac_Context_Record is record
      Source_Core  : Schild_Smp_Spinlock.Core_Id_Type := 0;
      Source_Label : Security_Label_Type := 1;
      Target_Label : Security_Label_Type := 1;
      Access_Ok    : Boolean := False;
   end record;

   procedure Enforce_Mac_Policy
     (Context : in out Mac_Context_Record)
   with Post => (if Context.Source_Label < Context.Target_Label then not Context.Access_Ok);
   --  BLP: a lower source may not grant access to a higher target.

end Schild_Smp_Mac;
