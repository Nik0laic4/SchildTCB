pragma Spark_Mode (On);

package body Schild_Ipc_Time_Guard is

   procedure Verify_Time_Window
     (Global_Uptime : in     Time_Tick;
      Start_Tick    : in     Time_Tick;
      End_Tick      : in     Time_Tick;
      Is_Valid      :    out Boolean)
   is
   begin
      --  Valid when the window is well-formed and covers the current time.
      if Start_Tick <= End_Tick and then
         Global_Uptime >= Start_Tick and then
         Global_Uptime <= End_Tick
      then
         Is_Valid := True;
      else
         Is_Valid := False;
      end if;
   end Verify_Time_Window;

end Schild_Ipc_Time_Guard;
