package body Schild_User_Reaper with
  SPARK_Mode => Off --  Scaffold: reports the target process as reaped.
is

   procedure Reap_Zombie_Process
     (Target_Pid : in     Pid_Type;
      Status     :    out Reaper_Status)
   is
   begin
      --  Scaffold: always report the reap as complete.
      Status := Reaper_Done;
   end Reap_Zombie_Process;

end Schild_User_Reaper;
