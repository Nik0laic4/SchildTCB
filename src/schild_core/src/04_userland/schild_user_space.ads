with Interfaces; use Interfaces;
with Schild_Mmu_Overseer; use Schild_Mmu_Overseer;

package Schild_User_Space with
  SPARK_Mode => On
is
   pragma Elaborate_Body;

   type Context_Id_Type is new Interfaces.Unsigned_32 range 1 .. 65535;
   
   type User_Context_Record is record
      Id            : Context_Id_Type := 1;
      Page_Dir_Base : Schild_Mmu_Overseer.Physical_Address := 0;
      Audit_Enabled : Boolean := False;
      Is_Active     : Boolean := False;
   end record;

   procedure Activate_User_Context
     (Context : in out User_Context_Record;
      Success :    out Boolean)
   with Pre  => Context.Page_Dir_Base /= 0,
        Post => (if Success then Context.Is_Active and Context.Audit_Enabled);

end Schild_User_Space;
