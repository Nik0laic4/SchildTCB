with Interfaces; use Interfaces;

package body Schild_User_Validator with
  SPARK_Mode => On
is

   procedure Validate_Task_Flags
     (Frame    : in     Task_Frame_Record;
      Is_Valid :    out Boolean)
   is
   begin
      --  Reject if privileged I/O (bits 12-13 of RFLAGS) are set.
      if (Frame.Target_RFLAGS and 16#3000#) = 0 then
         Is_Valid := True;
      else
         Is_Valid := False;
      end if;
   end Validate_Task_Flags;

end Schild_User_Validator;
