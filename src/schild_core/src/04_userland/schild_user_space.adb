with Schild_Mmu_Overseer; use Schild_Mmu_Overseer;

package body Schild_User_Space with
  SPARK_Mode => On
is

   procedure Activate_User_Context
     (Context : in out User_Context_Record;
      Success :    out Boolean)
   is
   begin
      -- 1. Security hook binding
      Context.Audit_Enabled := True;

      --  Activate only with a valid page directory and enabled audit.
      if Context.Page_Dir_Base /= 0 and Context.Audit_Enabled then
         Context.Is_Active := True;
         Success := True;
      else
         Success := False;
      end if;
   end Activate_User_Context;

end Schild_User_Space;
