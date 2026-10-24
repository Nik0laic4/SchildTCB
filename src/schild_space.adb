package body Schild_Space with SPARK_Mode is

   procedure Allocate_Space
     (Manager : in out Space_Manager;
      ASID    :        ASID_Index) is
   begin
      --  Mark the ASID active.
      Manager.ASID_Pool (ASID) := Space_Active;
      
      --  Increment the active-space count.
      Manager.Active_Spaces    := Manager.Active_Spaces + 1;
   end Allocate_Space;

end Schild_Space;
