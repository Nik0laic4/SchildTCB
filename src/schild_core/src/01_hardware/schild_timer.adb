package body Schild_Timer with
  SPARK_Mode => On
is

   procedure Update_System_Tick
     (Timer : in out Timer_Hardware_Record)
   is
   begin
      --  Advance the system tick counter.
      Timer.System_Ticks := Timer.System_Ticks + 1;
      Timer.Is_Running   := True;
   end Update_System_Tick;

end Schild_Timer;
