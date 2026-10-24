with Interfaces; use Interfaces;
with Schild_User_Thread;

package Schild_User_Reaper with
  SPARK_Mode => On
is

   type Pid_Type is new Interfaces.Unsigned_32 range 0 .. 1024;
   type Reaper_Status is (Reaper_Idle, Reaper_Active, Reaper_Done);

   procedure Reap_Zombie_Process
     (Target_Pid : in     Pid_Type;
      Status     :    out Reaper_Status)
   with Pre => Target_Pid > 1, --  Never reap the idle (0) or init (1) tasks.
        Post => Status = Reaper_Done;

end Schild_User_Reaper;
