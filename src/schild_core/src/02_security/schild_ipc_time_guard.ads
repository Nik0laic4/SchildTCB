pragma Spark_Mode (On);

package Schild_Ipc_Time_Guard is

   type Time_Tick is mod 2**64;

   --  A transfer is valid only within its [Start, End] time window.
   procedure Verify_Time_Window
     (Global_Uptime : in     Time_Tick;
      Start_Tick    : in     Time_Tick;
      End_Tick      : in     Time_Tick;
      Is_Valid      :    out Boolean)
   with
     Global  => null,
     Depends => (Is_Valid => (Global_Uptime, Start_Tick, End_Tick)),
     Post    => (if Is_Valid then 
                   Start_Tick <= End_Tick and
                   Global_Uptime >= Start_Tick and 
                   Global_Uptime <= End_Tick
                 else
                   Start_Tick > End_Tick or
                   Global_Uptime < Start_Tick or 
                   Global_Uptime > End_Tick);

end Schild_Ipc_Time_Guard;
