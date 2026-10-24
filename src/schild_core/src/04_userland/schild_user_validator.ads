with Interfaces; use Interfaces;

package Schild_User_Validator with
  SPARK_Mode => On
is

   --  A saved user-task frame; only RFLAGS is modelled in this scaffold.
   type Task_Frame_Record is record
      Target_RFLAGS : Interfaces.Unsigned_64;
      --  (Other registers are omitted in the public scaffold.)
   end record;

   procedure Validate_Task_Flags
     (Frame    : in     Task_Frame_Record;
      Is_Valid :    out Boolean);

end Schild_User_Validator;
