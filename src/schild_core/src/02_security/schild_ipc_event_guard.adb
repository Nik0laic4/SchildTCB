pragma Spark_Mode (On);

package body Schild_Ipc_Event_Guard is

   procedure Throttle_Asynchronous_Signal
     (Current_Time  : in     Time_Stamp;
      Last_Sent_Time : in     Time_Stamp;
      Is_Allowed    :    out Boolean)
   is
   begin
      --  Allow only after the minimum spacing has elapsed.
      if Current_Time >= Last_Sent_Time and then
         (Current_Time - Last_Sent_Time) >= MIN_SIGNAL_INTERVAL
      then
         Is_Allowed := True;
      else
         Is_Allowed := False;
      end if;
   end Throttle_Asynchronous_Signal;

end Schild_Ipc_Event_Guard;
