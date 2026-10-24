package body Schild_Mls_Time_Manager with
  SPARK_Mode => On
is
   procedure Validate_Access_Window
     (Window  : in out Time_Window_Record;
      Current : in     Security_Timestamp;
      Valid   :    out Boolean)
   is
   begin
      if Current >= Window.Start_Time and Current <= Window.End_Time then
         Window.Is_Expired := False;
         Valid := True;
      else
         Window.Is_Expired := True;
         Valid := False;
      end if;
   end Validate_Access_Window;
end Schild_Mls_Time_Manager;
