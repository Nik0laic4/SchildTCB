pragma Spark_Mode (On);

package Schild_Ipc_Event_Guard is

   type Time_Stamp is mod 2**64;

   --  Minimum spacing between asynchronous signals.
   MIN_SIGNAL_INTERVAL : constant Time_Stamp := 500;

   --  Allow a signal only after the minimum interval has elapsed.
   procedure Throttle_Asynchronous_Signal
     (Current_Time  : in     Time_Stamp;
      Last_Sent_Time : in     Time_Stamp;
      Is_Allowed    :    out Boolean)
   with
     Global  => null,
     Depends => (Is_Allowed => (Current_Time, Last_Sent_Time)),
     Post    => (if Is_Allowed then 
                   Current_Time >= Last_Sent_Time and 
                   (Current_Time - Last_Sent_Time) >= MIN_SIGNAL_INTERVAL
                 else 
                   Current_Time < Last_Sent_Time or 
                   (Current_Time - Last_Sent_Time) < MIN_SIGNAL_INTERVAL);

end Schild_Ipc_Event_Guard;
